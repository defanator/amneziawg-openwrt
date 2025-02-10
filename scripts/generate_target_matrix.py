#!/usr/bin/env python3
#
# python/async refactored version of https://github.com/Slava-Shchipunov/awg-openwrt/blob/master/index.js

import sys
import os
import re
import argparse
import logging
import json
import asyncio
import aiohttp
from bs4 import BeautifulSoup

logger = logging.getLogger(os.path.basename(__file__))

# filtered targets for release builds
TARGETS_TO_BUILD = ["ath79"]
SUBTARGETS_TO_BUILD = ["generic", "nand"]

# filtered targets for snapshot builds
SNAPSHOT_TARGETS_TO_BUILD = ["ath79"]
SNAPSHOT_SUBTARGETS_TO_BUILD = ["generic", "nand"]


class OpenWrtBuildInfoFetcher:
    def __init__(self, version):
        self._session = None
        self.url = "https://downloads.openwrt.org/"
        self.version = version.lower()

        if self.version == "snapshot":
            self.base_uri = "/snapshots/targets/"
        else:
            self.base_uri = f"/releases/{version}/targets/"

        self.targets = {}

    def __str__(self):
        return f"{self.__class__.__name__} ({self.url})"

    async def __aenter__(self):
        self._session = aiohttp.ClientSession(base_url=self.url)
        return self

    async def __aexit__(self, *err):
        await self._session.close()
        self._session = None

    async def get(self, url):
        async with self._session.get(
            os.path.join(self.base_uri, url.lstrip("/"))
        ) as response:
            response.raise_for_status()
            if response.status != 200:
                logger.error("error fetching %s: %d", url, response.status)
                raise Exception(f"Error fetching {url}")
            return await response.text()

    async def get_targets(self):
        logger.info("fetching targets")

        r = await self.get("/")
        s = BeautifulSoup(r, "html.parser")

        for element in s.select("table tr td.n a"):
            name = element.get("href")
            if name and name.endswith("/"):
                if len(TARGETS_TO_BUILD) > 0 and name[:-1] not in TARGETS_TO_BUILD:
                    continue
                self.targets[name[:-1]] = {}

    async def get_subtargets(self):
        logger.info("fetching subtargets")

        _jobs = []
        for target in self.targets:
            _jobs.append({"target": target, "url": f"{target}/"})

        res = await asyncio.gather(*(self.get(_job["url"]) for _job in _jobs))

        for i, _ in enumerate(_jobs):
            target = _jobs[i]["target"]
            s = BeautifulSoup(res[i], "html.parser")

            for element in s.select("table tr td.n a"):
                name = element.get("href")
                if name and name.endswith("/"):
                    if (
                        len(SUBTARGETS_TO_BUILD) > 0
                        and name[:-1] not in SUBTARGETS_TO_BUILD
                    ):
                        continue
                    self.targets[target][name[:-1]] = {
                        "vermagic": None,
                        "pkgarch": None,
                    }

    async def get_details(self):
        logger.info("fetching details")

        _jobs = []
        for target, subtargets in self.targets.items():
            for subtarget in subtargets:
                _jobs.append(
                    {
                        "target": target,
                        "subtarget": subtarget,
                        "url": f"{target}/{subtarget}/packages/",
                    }
                )

        res = await asyncio.gather(*(self.get(_job["url"]) for _job in _jobs))

        logger.info("parsing details")

        for i, _ in enumerate(_jobs):
            target = _jobs[i]["target"]
            subtarget = _jobs[i]["subtarget"]

            # BeautifulSoup solution (commented below) takes a while, so use plain regex here
            packages = re.findall(r'href="(kernel[_-].*[ia]pk)"', res[i])
            logger.debug("kernel packages found: %s", packages)
            for package in packages:
                logger.debug("%s/%s: found kernel: %s", target, subtarget, package)

                # regular (release) builds
                m = re.match(
                    r"kernel_\d+\.\d+\.\d+(?:-\d+)?[-~]([a-f0-9]+)(?:-r\d+)?_([a-zA-Z0-9_-]+)\.ipk$",
                    package,
                )
                if m:
                    self.targets[target][subtarget]["vermagic"] = m.group(1)
                    self.targets[target][subtarget]["pkgarch"] = m.group(2)
                    break

                # snapshot builds
                m = re.match(
                    r"kernel-\d+\.\d+\.\d+(?:-\d+)?[-~]([a-f0-9]+)(?:-r\d+)\.apk$",
                    package,
                )
                if m:
                    self.targets[target][subtarget]["vermagic"] = m.group(1)
                    # TODO: figure out how to populate this correctly
                    self.targets[target][subtarget]["pkgarch"] = "none"
                    break

            # s = BeautifulSoup(res[i], 'html.parser')
            # for element in s.select('a'):
            #    name = element.get('href')
            #    if name and name.startswith('kernel_'):
            #        logger.info("%s/%s: parsing %s", target, subtarget, element)
            #        m = re.match(r'kernel_\d+\.\d+\.\d+(?:-\d+)?[-~]([a-f0-9]+)(?:-r\d+)?_([a-zA-Z0-9_-]+)\.ipk$', name)
            #        if m:
            #            self.targets[target][subtarget]["vermagic"] = m.group(1)
            #            self.targets[target][subtarget]["pkgarch"] = m.group(2)
            #            break


async def main():
    parser = argparse.ArgumentParser(
        description="Generate build matrix for amneziawg-openwrt GitHub CI"
    )
    parser.add_argument(
        "version",
        help="OpenWrt version (use SNAPSHOT for building against snapshots)",
        nargs="+",
    )
    parser.add_argument(
        "--verbose", action="store_true", default=False, help="enable logging"
    )
    args = parser.parse_args()

    if args.verbose:
        logging.basicConfig(
            level=logging.DEBUG,
            format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        )

    logger.info("started")
    job_config = []

    versions = set()
    for version in args.version:
        if version.lower() in versions:
            logger.warning("duplicate version ignored: %s", version)
            continue
        versions.add(version.lower())

    try:
        for version in versions:
            async with OpenWrtBuildInfoFetcher(version=version) as of:
                await of.get_targets()
                await of.get_subtargets()
                await of.get_details()

            for target, subtargets in of.targets.items():
                for subtarget in subtargets:
                    job_config.append(
                        {
                            "tag": version,
                            "target": target,
                            "subtarget": subtarget,
                            "vermagic": of.targets[target][subtarget]["vermagic"],
                            "pkgarch": of.targets[target][subtarget]["pkgarch"],
                        }
                    )

        print(json.dumps(job_config, separators=(",", ":")))
    except Exception as exc:
        logger.error("%s", str(exc))
        return 1

    logger.info("stopped")

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
