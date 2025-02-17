##############################################
# $Id: myUtilsTemplate.pm 21509 2020-03-25 11:20:51Z rudolfkoenig $
#
# Save this file as 99_myUtils.pm, and create your own functions in the new
# file. They are then available in every Perl expression.

package main;

use strict;
use warnings;

sub
myUtils_Initialize($$)
{
  my ($hash) = @_;
}

# Enter you functions below _this_ line.

sub get_mqtt_device {
    # Use the first mqtt device
    # Get a list of all devices of type MQTT2_CLIENT
    my @mqtt_devices = devspec2array("TYPE=MQTT2_CLIENT");

    # Check if the list is not empty
    if (@mqtt_devices) {
        # Get the first item from the list
        my $mqtt = $mqtt_devices[0];

        # Check if the device exists in %defs
        if (exists $defs{$mqtt}) {
            # Return the device
            return $mqtt;
        }
        else {
            # Log an error message
            Log3 $mqtt, 1, "MQTT2_CLIENT device not found in %defs";
            # Return undef as the device was not found in %defs
            return undef;
        }
    }
    else {
        # Log an error message
        Log3 undef, 1, "No MQTT2_CLIENT devices found";

        # Return undef as no device was found
        return undef;
    }
}

sub MAX2HASSdiscovery {
    my ($device) = @_;

     # If you have multiple MQTT2_CLIENT devices, specify the name of the one you want to use here.
     # If you only have one MQTT2_CLIENT device, you can leave mqtt undefined.
    my $mqtt = undef;
    if (!defined $mqtt || $mqtt eq "") {
        $mqtt = get_mqtt_device();
    } elsif (!exists $defs{$mqtt}) {
        # Log an error message
        Log3 $mqtt, 1, "MQTT2_CLIENT device not found in %defs";
        # Return undef as the device was not found in %defs
        return undef;
    } elsif ($defs{$device}{TYPE} ne "MQTT2_CLIENT") {
        # $device is not of type MQTT2_CLIENT
        Log3 $mqtt, 1, "Device $device is not of type MQTT2_CLIENT";
    }

    # Get the device type using InternalVal
    my $manufacturer = InternalVal($device, "TYPE", undef);

    # Check if the device is of type "MAX"
    if ($manufacturer eq "MAX") {
        # Get the subdevice type using InternalVal
        my $model = InternalVal($device, "type", undef);
        my %device_types = (
            "HeatingThermostat" => "MAX! Radiator Thermostat",
            "ShutterContact" => "MAX! Window Sensor",
            "WallMountedThermostat" => "MAX! Wall Thermostat",
            "EcoSwitch" => "MAX! Eco Switch",
        );
	    # Get the address using InternalVal
        my $addr = InternalVal($device, "addr", undef);
        # Get the serial number using ReadingsVal
        my $serialnr = ReadingsVal($device, "SerialNr", undef);
        # Get the firmware version using ReadingsVal
        my $firmware = ReadingsVal($device, "firmware", undef);
        # Get the rooms using AttrVal
        my $room = AttrVal($device, "room", undef);
        if (defined $room) {
            # A device can be assigned to more than one room. If that is the case, take the first room. They are separated by commata.
            $room =~ s/,.*//;
        }

        # Build fhem deeplink
        my $url = "http://fhem.local:8083/fhem?detail=$device";

        my $mqtt_device_topic = "homeassistant/$device";

        my $fhemstatus = (split / /, AttrVal($mqtt, "lwt", ""))[0];

        my $device_payload = {
            manufacturer => "eQ-3",
            model => $device_types{$model},
            name => $device,
            identifiers => [$addr],
            configuration_url => $url,
            suggested_area => $room,
        };
        $device_payload->{sw_version} = $firmware if defined $firmware;
        
        my $availability_payload = [
            {
                topic=>$fhemstatus,
                payload_available=>"online",
                payload_not_available=>"offline"
            },
            {
                topic=>"$mqtt_device_topic/Activity",
                payload_available=>"alive",
                payload_not_available=>"dead"
            }
        ];


        # Make sure the device exports data to MQTT
        if (! defined AttrVal($device, "mqttPublish", undef)) {
            fhem("attr $device mqttPublish *:topic={\"\$base/\$device/\$name\"}");
        }
        # Make sure there are no mqttDefaults
        if (defined AttrVal($device, "mqttDefaults", undef)) {
            fhem("deleteattr $device mqttDefaults");
        }

        # Declare mqtt_sensor_topic and mqtt_payload, which will be (re-)used for each sensor below.
        my $mqtt_sensor_topic;
        my $mqtt_payload;

        # Register battery sensor for all devices
        $mqtt_sensor_topic = "homeassistant/binary_sensor/$device/$addr-battery/config";
        $mqtt_payload = {
            object_id=>"$manufacturer-$model-$addr-battery",
            device_class=>"battery",
            entity_category=>"diagnostic",
            state_topic=>"$mqtt_device_topic/batteryState",
            unique_id=>"$manufacturer-$model-$addr-battery",
            payload_off=>"ok",
            payload_on=>"low",
            device=>$device_payload,
            availability=>$availability_payload,
            availability_mode=>"all"
        };
        $mqtt_payload = toJSON($mqtt_payload);
        fhem("set $mqtt publish $mqtt_sensor_topic $mqtt_payload");

        # Register RSSI sensor for all devices
        $mqtt_sensor_topic = "homeassistant/sensor/$device/$addr-signal/config";
        $mqtt_payload = {
            object_id=>"$manufacturer-$model-$addr-signal",
            device_class=>"signal_strength",
            unit_of_measurement=>"dBm",
            entity_category=>"diagnostic",
            state_topic=>"$mqtt_device_topic/RSSI",
            unique_id=>"$manufacturer-$model-$addr-signal",
            device=>$device_payload,
            availability=>$availability_payload,
            availability_mode=>"all"
        };
        $mqtt_payload = toJSON($mqtt_payload);
        fhem("set $mqtt publish $mqtt_sensor_topic $mqtt_payload");

        # Check if the device is a ShutterContact
        if ($model eq "ShutterContact") {
            # Register window contact
            $mqtt_sensor_topic = "homeassistant/binary_sensor/$device/$addr-window/config";
            $mqtt_payload = {
                name=>undef,
                object_id=>"$manufacturer-$model-$addr-window",
                device_class=>"window",
                state_topic=>"$mqtt_device_topic/state",
                unique_id=>"$manufacturer-$model-$addr-window",
                payload_off=>"closed",
                payload_on=>"opened",
                device=>$device_payload,
                availability=>$availability_payload,
                availability_mode=>"all"
            };
            $mqtt_payload = toJSON($mqtt_payload);
            fhem("set $mqtt publish $mqtt_sensor_topic $mqtt_payload");
        }

        # Check if the device is a HeatingThermostat
        if ($model eq "HeatingThermostat") {
            # valve
            my $hass_device_name = "climate." . lc($manufacturer . "_" . $model . "_" . $addr) . "_climate";
            my $action_template = "{% set valve_position = state_attr($hass_device_name', 'valve_position') %} {% set temperature = state_attr($hass_device_name, 'temperature') %} {% if valve_position > 0 %}  heating {% elif valve_position == 0 and temperature > 4.5 %} idle {% elif valve_position == 0 and temperature == 4.5 %} off {% endif %}";
            $mqtt_sensor_topic = "homeassistant/valve/$device/$addr-valve/config";
            $mqtt_payload = {
                object_id=>"$manufacturer-$model-$addr-valve",
                entity_category=>"diagnostic",
                reports_position=>"true",
                state_topic=>"$mqtt_device_topic/valveposition",
                device_class=>"water",
                unique_id=>"$manufacturer-$model-$addr-valve",
                device=>$device_payload,
                availability=>$availability_payload,
                availability_mode=>"all"
            };
            $mqtt_payload = toJSON($mqtt_payload);
            fhem("set $mqtt publish $mqtt_sensor_topic $mqtt_payload");
        }

        # Check if the device is a HeatingThermostat or WallMountedThermostat
        if ($model eq "HeatingThermostat" || $model eq "WallMountedThermostat") {
            # Climate device
            my $hass_device_name = "climate." . lc($manufacturer . "_" . $model . "_" . $addr) . "_climate";
            my $minimumTemperature = ReadingsVal($device, "minimumTemperature", "off");
            if ($minimumTemperature eq "off") {
                $minimumTemperature = 4.5;
            } elsif ($minimumTemperature eq "on") {
                $minimumTemperature = 30.5;
            }

            my $maximumTemperature = ReadingsVal($device, "maximumTemperature", "on");
            if ($maximumTemperature eq "on") {
                $maximumTemperature = 30.5;
            } elsif ($maximumTemperature eq "off") {
                $maximumTemperature = 4.5;
            }

            my $modes = [qw(auto heat off)];
            #my $mode_state_template = "{% set values = {'boost': none, 'manual': 'heat'} %} {{ values[value] | default(value) }}";
            my $mode_state_template = "{% set values = { 'boost': none, 'manual': 'heat' } %} {% if is_state_attr('$hass_device_name', 'temperature', 4.5) and value == 'manual' %} off {% else %} {{ values[value] | default(value) }} {% endif %}";
            my $mode_command_template = "{% set values = { 'heat': state_attr('$hass_device_name', 'temperature') } %} {{ values[value] | default(value) }}";
            
            my $preset_modes = [qw(eco boost comfort)];
            my $preset_mode_command_template = "{% if is_state('$hass_device_name', 'auto') and value != 'boost' %} auto {{ value }} {% else %} {{ value }} {% endif %}";

            my $temperature_state_template = "{% set values = { 'off': 4.5, 'on': 30.5 } %} {{ values[value] | default(value) }}";
            my $temperature_command_template = "{% if is_state('$hass_device_name', 'auto') %} auto {{ value }} {% else %} {{ value }} {% endif %}";
            	    
            $mqtt_sensor_topic = "homeassistant/climate/$device/$addr-climate/config";
            $mqtt_payload = {
                name=>undef,
                object_id=>"$manufacturer-$model-$addr-climate",
                current_temperature_topic=>"$mqtt_device_topic/temperature",
                temperature_state_template=>"$temperature_state_template",
                temperature_command_topic=>"$mqtt_device_topic/set",
                temperature_command_template=>"$temperature_command_template",
                mode_command_topic=>"$mqtt_device_topic/set",
                temperature_state_topic=>"$mqtt_device_topic/desiredTemperature",
                mode_state_topic=>"$mqtt_device_topic/mode",
                preset_mode_state_topic=>"$mqtt_device_topic/preset",
                unique_id=>"$manufacturer-$model-$addr-climate",
                modes=>$modes,
                mode_state_template=>"$mode_state_template",
                mode_command_template=>"$mode_command_template",
                preset_modes=>$preset_modes,
                preset_mode_command_topic=>"$mqtt_device_topic/set",
                preset_mode_command_template=>"$preset_mode_command_template",
                precision=>0.5,
                min_temp=>4.5,
                max_temp=>30.5,
                temp_step=>0.5,
                device=>$device_payload,
                availability=>$availability_payload,
                availability_mode=>"all"
            };
            $mqtt_payload = toJSON($mqtt_payload);
            fhem("set $mqtt publish $mqtt_sensor_topic $mqtt_payload");
	  
            # Panel lock device
            $mqtt_sensor_topic = "homeassistant/binary_sensor/$device/$addr-panel/config";
            $mqtt_payload = {
                object_id=>"$manufacturer-$model-$addr-panel",
                device_class=>"lock",
                entity_category=>"diagnostic",
                state_topic=>"$mqtt_device_topic/panel",
                unique_id=>"$manufacturer-$model-$addr-panel",
                payload_off=>"locked",
                payload_on=>"unlocked",
                device=>$device_payload,
                availability=>$availability_payload,
                availability_mode=>"all"
            };
            $mqtt_payload = toJSON($mqtt_payload);
            fhem("set $mqtt publish $mqtt_sensor_topic $mqtt_payload");

            # Subscribe to desiredTemperature
            if (! defined AttrVal($device, "mqttSubscribe", undef)) {
                fhem("attr $device mqttSubscribe desiredTemperature:stopic={\"\$base/\$device/set\"}");
            }
            # Generate preset userReading
            if (! defined AttrVal($device, "userReadings", undef)) {
                fhem("attr $device userReadings preset {ReadingsVal(\$name, \"mode\", 0) eq \"boost\" ? \"boost\" : ReadingsVal(\$name, \"desiredTemperature\", 0) eq ReadingsVal(\$name, \"ecoTemperature\", 0) ? \"eco\" : ReadingsVal(\$name, \"desiredTemperature\", 0) eq ReadingsVal(\$name, \"comfortTemperature\", 0) ? \"comfort\" : \"none\" }");
            }
        }
    }
}


1;
