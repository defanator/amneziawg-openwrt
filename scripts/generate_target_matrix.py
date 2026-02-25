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
import yaml
from bs4 import BeautifulSoup

logger = logging.getLogger(os.path.basename(__file__))


class OpenWrtBuildInfoFetcher:
    def __init__(self, version, target_config):
        self._session = None
        self.url = "https://downloads.openwrt.org/"
        self.version = version.lower()
        self.target_config = target_config

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
                target_name = name[:-1]
                if target_name in self.target_config:
                    self.targets[target_name] = {}

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
                    subtarget_name = name[:-1]
                    if subtarget_name in self.target_config[target]:
                        self.targets[target][subtarget_name] = {
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

    def validate_config(self):
        """Validate that all configured targets/subtargets exist on downloads site."""
        missing_combinations = []

        for target in self.target_config:
            if target not in self.targets:
                for subtarget in self.target_config[target]:
                    missing_combinations.append(f"{target}/{subtarget}")
            else:
                for subtarget in self.target_config[target]:
                    if subtarget not in self.targets[target]:
                        missing_combinations.append(f"{target}/{subtarget}")

        if missing_combinations:
            logger.error(
                "Invalid target/subtarget combinations found in configuration:"
            )
            for combo in sorted(missing_combinations):
                logger.error("  - %s", combo)
            logger.error(
                "These combinations do not exist on the OpenWrt downloads site."
            )
            raise Exception(
                f"Validation failed: {len(missing_combinations)} invalid target/subtarget combinations"
            )


async def main():
    parser = argparse.ArgumentParser(
        description="Generate build matrix for amneziawg-openwrt GitHub CI"
    )
    parser.add_argument(
        "--config",
        required=True,
        help="YAML configuration file specifying OpenWrt versions and targets",
    )
    parser.add_argument(
        "version",
        nargs="*",
        help="OpenWrt version(s) to build (must exist in config file). If none specified, returns empty array.",
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

    # Load YAML configuration
    try:
        with open(args.config, "r", encoding="utf-8") as config_file:
            config = yaml.safe_load(config_file)
    except FileNotFoundError:
        logger.error("Configuration file not found: %s", args.config)
        return 1
    except yaml.YAMLError as e:
        logger.error("Error parsing YAML configuration: %s", e)
        return 1

    if not isinstance(config, dict):
        logger.error(
            "Invalid configuration format: expected dictionary with version keys"
        )
        return 1

    # If no versions specified, return empty array
    if not args.version:
        logger.info("No versions specified, returning empty array")
        print(json.dumps(job_config, separators=(",", ":")))
        logger.info("stopped")
        return 0

    # Validate that all specified versions exist in config
    missing_versions = []
    for version in args.version:
        if version not in config:
            missing_versions.append(version)

    if missing_versions:
        logger.error(
            "The following versions are not found in config file %s: %s",
            args.config,
            ", ".join(missing_versions),
        )
        logger.error("Available versions in config: %s", ", ".join(config.keys()))
        return 1

    # Process only the specified versions
    versions_to_process = set(args.version)

    try:
        for version_str, target_config in config.items():
            # Skip versions not requested
            if version_str not in versions_to_process:
                continue

            if not isinstance(target_config, dict):
                logger.warning(
                    "Skipping invalid target config for version %s: expected dictionary",
                    version_str,
                )
                continue

            logger.info("Processing version: %s", version_str)

            async with OpenWrtBuildInfoFetcher(
                version=version_str, target_config=target_config
            ) as of:
                await of.get_targets()
                await of.get_subtargets()
                await of.get_details()
                of.validate_config()

            for target, subtargets in of.targets.items():
                for subtarget in subtargets:
                    job_config.append(
                        {
                            "tag": version_str,
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
