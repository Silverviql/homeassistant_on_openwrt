#!/bin/sh
# Homeassistant installer script by @devbis, modified for SONOFF Zigbee 3.0 USB Dongle Plus-E on OpenWRT 24.10.1

get_ha_version()
{
  wget -q -O- https://pypi.org/simple/homeassistant/ | grep ${HOMEASSISTANT_MAJOR_VERSION} | tail -n 1 | cut -d "-" -f2 | cut -d "." -f1,2,3
}

get_python_version()
{
  opkg list | grep python3-base | head -n 1 | grep -Eo '[[:digit:]]+\.[[:digit:]]+'
}

get_version()
{
  local pkg=$1
  cat /tmp/ha_requirements.txt | grep -i -m 1 "${pkg}[<=>]=" | sed 's/.*[<=>]=\(.*\)/\1/g'
}

version()
{
  local pkg=$1
  echo "$pkg==$(get_version $pkg)"
}

is_lumi_gateway()
{
  cat /etc/board.json | grep -E '(dgnwg05lm|zhwg11lm)' | tr -s '"' | cut -d\" -f4
}

is_gtw360()
{
  cat /etc/board.json | grep 'gtw360' | tr -s '"' | cut -d\" -f4
}

int_version() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

set -e

HOMEASSISTANT_MAJOR_VERSION="2024.3"
export PIP_DEFAULT_TIMEOUT=100

HOMEASSISTANT_VERSION=$(get_ha_version)
STORAGE_TMP="/root/tmp-ha"  # /tmp in RAM too small, additional tmp on flash drive

if [ "${HOMEASSISTANT_VERSION}" = "" ]; then
  echo "Incorrect Home Assistant version. Exiting ...";
  exit 1;
fi

echo "=========================================="
echo " Installing Home Assistant ${HOMEASSISTANT_VERSION} ..."
echo "=========================================="

(
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/homeassistant/package_constraints.txt -O -
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/requirements.txt -O -
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/requirements_all.txt -O -
# now we can fetch nabucasa version and its deps
wget -q https://raw.githubusercontent.com/NabuCasa/hass-nabucasa/"$(get_version hass-nabucasa)"/setup.py -O - | grep '[>=]=' | sed -E 's/\s*"(.*)",?/\1/'
) >/tmp/ha_requirements.txt

# Ensure compatible bellows version for SONOFF Zigbee 3.0 USB Dongle Plus-E
echo "bellows>=0.36.0" >> /tmp/ha_requirements.txt

HOMEASSISTANT_FRONTEND_VERSION=$(get_version home-assistant-frontend)
NABUCASA_VER=$(get_version hass-nabucasa)
ZIGPY_ZBOSS_VER=1.2.0

if pgrep -a -f "usr/bin/hass"; then
  echo "Stop running process of Home Assistant (and HASS Configurator) to free RAM for installation";
  exit 1;
fi

rm -rf ${STORAGE_TMP}

echo "Install base requirements from feed..."
opkg update || { echo "Error: opkg update failed. Check network and repositories."; exit 1; }

# Install USB-related packages for SONOFF Zigbee 3.0 USB Dongle Plus-E
opkg install kmod-usb-serial kmod-usb-acm usbutils

PYTHON_VERSION=$(get_python_version)
echo "Detected Python ${PYTHON_VERSION}"
LUMI_GATEWAY=$(is_lumi_gateway)
GTW360_GATEWAY=$(is_gtw360)
# Enable ZHA for SONOFF Zigbee 3.0 USB Dongle Plus-E if USB serial port is detected
if [ -n "$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null)" ]; then
  SONOFF_ZIGBEE="true"
else
  SONOFF_ZIGBEE=""
fi
NEED_ZHA="$LUMI_GATEWAY$GTW360_GATEWAY$SONOFF_ZIGBEE"

# Install them first to check Openlumi feed is added
opkg install \
  python3-base \
  python3-pynacl \
  python3-ciso8601

opkg install \
  patch \
  unzip \
  libjpeg-turbo \
  python3-aiohttp \
  python3-aiohttp-cors \
  python3-async-timeout \
  python3-asyncio \
  python3-attrs \
  python3-bcrypt \
  python3-boto3 \
  python3-botocore \
  python3-certifi \
  python3-cffi \
  python3-cgi \
  python3-cgitb \
  python3-chardet \
  python3-codecs \
  python3-cryptodome \
  python3-cryptodomex \
  python3-cryptography \
  python3-ctypes \
  python3-dateutil \
  python3-dbm \
  python3-decimal \
  python3-defusedxml \
  python3-distutils \
  python3-docutils \
  python3-email \
  python3-greenlet \
  python3-idna \
  python3-jinja2 \
  python3-jmespath \
  python3-light \
  python3-logging \
  python3-lzma \
  python3-markupsafe \
  python3-multidict \
  python3-multiprocessing \
  python3-ncurses \
  python3-netdisco \
  python3-netifaces \
  python3-openssl \
  python3-pillow \
  python3-pip \
  python3-pkg-resources \
  python3-ply \
  python3-psutil \
  python3-pycparser \
  python3-pydoc \
  python3-pyopenssl \
  python3-pytz \
  python3-requests \
  python3-s3transfer \
  python3-setuptools \
  python3-six \
  python3-slugify \
  python3-sqlalchemy \
  python3-sqlite3 \
  python3-uuid \
  python3-unittest \
  python3-urllib \
  python3-urllib3 \
  python3-xml \
  python3-yaml \
  python3-yarl

# Verify python3-pip installation
if ! command -v pip3 >/dev/null 2>&1; then
  echo "Error: pip3 not found. Attempting to reinstall python3-pip..."
  opkg update || { echo "Error: opkg update failed during pip3 reinstall. Check network and repositories."; exit 1; }
  opkg install python3-pip || { echo "Error: Failed to install python3-pip. Check opkg repositories and available space."; exit 1; }
fi

# openwrt < 22.03 doesn't have this package
opkg install python3-pycares 2>/dev/null || true
if [ $BROKEN_NUMPY ]; then
  # on intel N100 it might use missing CPU instructions. Remove it
  opkg remove python3-numpy 2>/dev/null || true
else
  # numpy requires hard floating point support and is missing on some MIPS architectures
  opkg install python3-numpy 2>/dev/null || true
fi

cd /tmp/

rm -rf /etc/homeassistant/deps/
find /usr/lib/python${PYTHON_VERSION}/site-packages/ | grep -E "/__pycache__$" | xargs rm -rf
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/botocore/data
find /usr/lib/python${PYTHON_VERSION}/site-packages/numpy -iname tests -print0 | xargs -0 rm -rf

echo "Install base requirements from PyPI..."
pip3 install --no-cache-dir --root-user-action=ignore wheel || { echo "Error: Failed to install wheel package."; exit 1; }
pip3 freeze > /tmp/freeze.txt
grep -E 'aiohttp|async-timeout|crypto|YAML' /tmp/freeze.txt > /tmp/owrt_constraints.txt

cat << EOF > /tmp/requirements_nodeps.txt
$(version aioesphomeapi)
$(version esphome-dashboard-api)
$(version zeroconf)
EOF

mkdir -p ${STORAGE_TMP}

TMPDIR=${STORAGE_TMP} pip3 install --no-cache-dir --no-deps --root-user-action=ignore -r /tmp/requirements_nodeps.txt
# add zeroconf
grep 'zeroconf' /tmp/requirements_nodeps.txt >> /tmp/owrt_constraints.txt
# fix deps
sed -i -e 's/cryptography\(.*\)/cryptography >=36.0.2/' -e 's/chacha20poly1305-reuseable\(.*\)/chacha20poly1305-reuseable >=0.10.0/' /usr/lib/python${PYTHON_VERSION}/site-packages/aioesphomeapi-23.0.0.dist-info/METADATA

cat << EOF > /tmp/requirements.txt
tzdata>=2021.2.post0  # 2021.6+ requirement

$(version atomicwrites-homeassistant)  # nabucasa dep
$(version snitun)  # nabucasa dep
$(version home-assistant-frontend)
$(version hass-nabucasa)
EOF

if [ -n "${NEED_ZHA}" ]; then
  echo "$(version zigpy-zboss)" >> /tmp/requirements.txt
  echo "$(version bellows)" >> /tmp/requirements.txt
  echo "$(version zigpy)" >> /tmp/requirements.txt
  echo "$(version zha-quirks)" >> /tmp/requirements.txt
fi

pip3 install --no-cache-dir --constraint /tmp/owrt_constraints.txt -r /tmp/requirements.txt

if [ -n "${NEED_ZHA}" ]; then
  # bellows doesn't install patched version
  pip3 install --no-cache-dir --constraint /tmp/owrt_constraints.txt $(version bellows)
fi

pip3 install --no-cache-dir --constraint /tmp/owrt_constraints.txt homeassistant==${HOMEASSISTANT_VERSION}

if [ ! -d /etc/homeassistant ]; then
  mkdir -p /etc/homeassistant
fi

cat << EOF > /etc/homeassistant/configuration.yaml
# Configure a default setup of Home Assistant (frontend, api, etc)
default_config:

http:
  server_host: 0.0.0.0
  server_port: 8123

# Text to speech
tts:
  - platform: google_translate
EOF

if [ -n "${NEED_ZHA}" ]; then
  cat << EOF >> /etc/homeassistant/configuration.yaml

zha:
  zigbee_device: /dev/ttyUSB0
EOF
fi

cat << EOF > /etc/init.d/homeassistant
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
PROG=/usr/bin/hass
start_service() {
  . /lib/functions.sh
  procd_open_instance
  procd_set_param command \$PROG --config /etc/homeassistant --script ensure_config
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_set_param respawn
  procd_close_instance
}
EOF

chmod +x /etc/init.d/homeassistant
/etc/init.d/homeassistant enable

echo "Starting Home Assistant..."
/etc/init.d/homeassistant start

sleep 5

IP=$(uci get network.lan.ipaddr)
echo "Installation complete!"
echo "Access Home Assistant at http://$IP:8123"
echo "ZHA configured for SONOFF Zigbee 3.0 USB Dongle Plus-E at /dev/ttyUSB0"
echo "Check logs at /var/log/home-assistant.log if issues occur"
