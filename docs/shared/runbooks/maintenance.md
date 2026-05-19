# Maintenance

## Safe Upgrade

```sh
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y autoremove --purge
sudo apt-get clean
```

## Full Upgrade

```sh
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get -y dist-upgrade
sudo apt-get -y autoremove --purge
sudo apt-get clean
```

## Remove Ansible Backup Files

```sh
find . -type f -regex ".*[0-9]{4}-[0-9]{2}-[0-9]{2}@[0-9]{2}:[0-9]{2}:[0-9]{2}~" -ok rm {} \;
```
