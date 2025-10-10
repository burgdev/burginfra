---
title: Immich
order: 20
---
<a target="_blank" href="https://immich.app"><img src="/logos/immich_with_name.png" width="300"/></a>

[Immich](https://immich.app) is a self-hosted photo and video backup solution that provides a Google Photos-like experience.

## Scripts

- [`scripts/immich/bui-immich-auto-album`](scripts/immich/bui-immich-auto-album)
- [`scripts/immich/immich-takeouts-update`](scripts/immich/immich-takeouts-update)
- [`scripts/immich/immich-update-config`](scripts/immich/immich-update-config)

## Using Google Takeout data

Download the data from google take out and run the post-processing script (if needed):

```bash
../../scripts/immich/upate-takeout "$HOME/Downloads/takeouts/takeout-*.zip" takeouts
```

After this run the `immich-go` script:


### `immich-go` installation

[`immich-go`](https://github.com/simulot/immich-go) can be used to import all you photos.

```bash
VERSION="v0.27.0" # or just main
git clone https://github.com/simulot/immich-go.git
cd immich-go
git checkout $VERSION
go build
go install
export PATH=$PATH:$(go env GOPATH)/bin
```

During the first (and large) initialization it is recommaned to turn of storage template in the `config.template.json` file.
If you do this you need to restart `immich` (`docker compose down; docker compose up`).
If all jobs are done (can take a very long time (days)), you can enable it and run the storage path migration job.

Run the script import script:

```bash
# make sure immich is running
# either with docker or kubernetes
# docker up # or kubectl get pods -n immich
API_KEY=my_key # TODO: create an api key with all permissions
immich-go upload from-google-photos -k $API_KEY -s http://localhost:2283/ --takeout-tag --tag from_google takeouts/takeout-*.zip
```


### Delete all Albums

The [`immich-auto-album`](https://github.com/Salvoxia/immich-folder-album-creator) script can be used to delete all albums.

```bash
# make sure immich is running
# either with docker or kubernetes
# docker up # or kubectl get pods -n immich
export API_KEY="my_key"
. ../../scripts/bin/activate # source activate script
bui-immich-auto-album -m DELETE_ALL --delete-confirm / http://localhost:2283/api $API_KEY
```
## Resources

- [Official Documentation](https://immich.app/docs)
- [GitHub Repository](https://github.com/immich-app/immich)
- [Community Support](https://github.com/immich-app/immich/discussions)
