# Vendor dependencies

`Scripts/bootstrap.sh` places the Mojang-compatible Bedrock LevelDB fork in
`Vendor/leveldb-mcpe` and records the exact resolved commit in
`Vendor/leveldb-mcpe.lock`.

The dependency is intentionally not duplicated in this source archive. Its own
BSD-3-Clause license remains applicable to that directory.
