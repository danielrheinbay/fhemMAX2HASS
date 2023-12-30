# fhemMAX2HASS
Integrate [eQ-3 MAX!](https://www.eq-3.de/produkte/max.html) devices into [Home Assistant](https://www.home-assistant.io/) using [FHEM](https://fhem.de/) instead of the vendor's proprietary MAX Cube LAN Gateway.
Home Assistant has a built-in [eQ-3 MAX! integration](https://www.home-assistant.io/integrations/maxcube/), but it requires the vendor's proprietary [MAX Cube LAN Gateway](https://www.eq-3.de/produkte/max/detail/bc-lgw-o-tw.html). This is no longer available, no longer supported by the vendor, and has a reputation to "forget" its configuration. Also, eQ-3 has shutdown all MAX!-related cloud services in July 2023.

## Prerequisites
* a working [Home Assistant](https://www.home-assistant.io/) instance
* a working [FHEM](https://fhem.de/) instance
* a working MQTT broker, e.g. [Eclipse Mosquitto™](https://mosquitto.org/)
* eQ-3 MAX! hardware configured to work with FHEM (see [FHEM Wiki](https://wiki.fhem.de/wiki/MAX))

## Installation
* Copy `MAX2HASSdiscovery` from [99_myUtils.pm](99_myUtils.pm) into your `99_myUtils.pm` (see [FHEM Wiki](https://wiki.fhem.de/wiki/99_myUtils_anlegen) for detailed instructions).  
  **Note:** Make sure you paste the code between the lines `# Enter you functions below _this_ line.` and `1;`, keeping both intact.
* Change the host name in `my $url = "http://fhem.local:8083/fhem?detail=$device";` ([99_myUtils.pm#L46](99_myUtils.pm#L46)) to point to your FHEM instance.

## Configuration

### FHEM
* Backup your `fhem.cfg`, just in case anything goes wrong.
* Configure a connection to your MQTT broker using the [MQTT2_CLIENT](https://fhem.de/commandref.html#MQTT2_CLIENT) module:  
  ```
  define mqtt MQTT2_CLIENT <mymqttbroker.local>:1883
  attr mqtt lwt homeassistant/binary_sensor/fhem/availability offline
  attr mqtt lwtRetain 1
  attr mqtt msgAfterConnect -r homeassistant/binary_sensor/fhem/availability online
  attr mqtt msgBeforeDisconnect -r homeassistant/binary_sensor/fhem/availability offline
  ```
* Configure an [MQTT Generic Bridge](https://commandref.fhem.de/commandref.html#MQTT_GENERIC_BRIDGE):  
  ```
  define mqttGenericBridge MQTT_GENERIC_BRIDGE
  attr mqttGenericBridge IODev mqtt
  attr mqttGenericBridge globalDefaults base="homeassistant" qos=2 retain=1
  attr mqttGenericBridge stateFormat dev: device-count in: incoming-count out: outgoing-count
  ```
* Add a trigger to call MAX2HASSdiscovery using the [DOIF](https://commandref.fhem.de/commandref.html#DOIF) module:  
  ```
  define hass.MAXdiscovery DOIF ([":Activity",""]) ({MAX2HASSdiscovery("$DEVICE")})
  attr hass.MAXdiscovery do always
  ```
* For each MAX! device that you would like to integrate to FHEM: set its actCycle attribute to 12:00:  
  `attr <myMaxDevice> actCycle 12:00`

### Home Assistant
* Backup your Home Assistant `config` directory, just in case anything goes wrong.
* Configure a connection to your MQTT broker using the [MQTT integration](https://www.home-assistant.io/integrations/mqtt/).
  `MAX2HASSdiscovery` then uses Home Assistant's [MQTT discovery protocol](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery) to configure all devices automatically. You should find all MAX! devices after a couple of minutes. If not, trigger an activity, e.g. open/close a window shutter or change the mode or temperature of a thermostat.
* In your dashboard, add cards as neeeded, e.g.
  ```
  type: tile
  entity: climate.max_wallmountedthermostat_123abc_climate
  features:
    - style: icons
      hvac_modes:
        - auto
        - 'off'
      type: climate-hvac-modes
    - type: target-temperature
    - style: icons
      preset_modes:
        - eco
        - comfort
        - boost
      type: climate-preset-modes

## Supported MAX! devices
* [Radiator Thermostat](https://www.eq-3.de/Downloads/eq3/downloads_produktkatalog/max/bda_portal/BC-RT-TRX-CyG-3_UM_EN.pdf)
* [Radiator Thermostat+](https://www.eq-3.de/Downloads/eq3/downloads_produktkatalog/max/bda_portal/BC-RT-TRX-CyG-4_UM_EN.pdf) (not tested)
* [Radiator Thermostat basic](https://www.eq-3.de/Downloads/eq3/downloads_produktkatalog/max/bda_portal/BC-RT-TRX-CyN_UM_EN.pdf)
* [Wall Thermostat+](https://www.eq-3.de/Downloads/eq3/downloads_produktkatalog/max/bda_portal/BC-TC-C-WM-4_UM_EN.pdf)
* [Window Sensor](https://www.eq-3.de/Downloads/eq3/downloads_produktkatalog/max/bda_portal/BC-SC-Rd-WM-2_UM_EN.pdf)

## Limitations
* This integration deliberately does not allow thermostats to be set to their maximum temperature ("On" mode).
* The following eQ-3 MAX! devices are not yet supported (Pull Requests welcome!):
  * [Eco Switch](https://www.eq-3.de/produkte/max/detail/bc-pb-2-wm.html)
  * [Plug Adapter](https://www.eq-3.de/Downloads/eq3/downloads_produktkatalog/max/bda/BC-TS-Sw-Pl_UM_GE_eQ-3_130415.pdf)
