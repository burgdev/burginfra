## Immich Installation

From the [docu](https://immich.app/docs/install/docker-compose):


```bash
cp .env.template .env
vim .env # change all variables with a TODO
./update-config.sh # creates the immich.config.json file
```

```bash
docker compose up
```

Open the browser at `localhost:2283`.

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
docker up # make sure immich is running
API_KEY=my_key # TODO: create an api key with all permissions
immich-go upload from-google-photos -k $API_KEY -s http://localhost:2283/ --takeout-tag --tag from_google takeouts/takeout-*.zip
```


### Delete all Albums

The [`immich-auto-album`](https://github.com/Salvoxia/immich-folder-album-creator) script can be used to delete all albums.

```bash
export API_KEY="my_key"
. ../../scripts/bin/activate # source activate script
bui-immich-auto-album -m DELETE_ALL --delete-confirm / http://localhost:2283/api $API_KEY
```

