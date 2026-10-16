#!/usr/bin/with-contenv sh
# ==============================================================================
# Z2M Hue Tools - Home Assistant Add-on
# Reads config from HA add-on options and runs the applier
# ==============================================================================

echo "[INFO] Starting Z2M Hue Tools..."

# HA places add-on options at /data/options.json
OPTIONS_PATH="/data/options.json"

if [ ! -f "${OPTIONS_PATH}" ]; then
  echo "[ERROR] Options file not found at ${OPTIONS_PATH}"
  exit 1
fi

# Build the config JSON that our app expects from the HA options
CONFIG_PATH="/app/addon-options.json"

# Use node to transform the flat HA options into our nested config format
node -e "
(async () => {
const opts = require('${OPTIONS_PATH}');
const config = {
  mqtt: {
    host: opts.mqtt_host || 'core-mosquitto',
    port: opts.mqtt_port || 1883,
    username: opts.mqtt_username || '',
    password: opts.mqtt_password || ''
  },
  zigbee2mqtt_topic: opts.zigbee2mqtt_topic || 'zigbee2mqtt',
  hue_native_control: opts.hue_native_control || 'unchanged',
  hue_power_on_behavior: opts.hue_power_on_behavior || 'unchanged',
  hue_power_on_brightness: opts.hue_power_on_brightness || '',
  hue_power_on_color_temperature: opts.hue_power_on_color_temperature || '',
  hue_power_on_color: opts.hue_power_on_color || '',
  apply_to_groups: opts.apply_to_groups !== false,
  devices: opts.devices || [],
  run_interval: opts.run_interval || 'weekly',
  enable_notifications: opts.enable_notifications !== false,
  dry_run: opts.dry_run === true,
  debug: opts.debug === true
};
// Blank username: use the credentials the Supervisor issues to this add-on for
// the Mosquitto add-on (services: mqtt:need), so no password lives in options.
if (!config.mqtt.username) {
  try {
    const res = await fetch('http://supervisor/services/mqtt', {
      headers: { Authorization: 'Bearer ' + process.env.SUPERVISOR_TOKEN }
    });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const svc = (await res.json()).data;
    if (svc.host === config.mqtt.host) {
      config.mqtt.username = svc.username;
      config.mqtt.password = svc.password;
      console.log('[INFO] MQTT credentials: provided by the Supervisor MQTT service');
    } else {
      console.log('[INFO] MQTT credentials: none (broker ' + config.mqtt.host + ' is not the Supervisor MQTT service at ' + svc.host + ')');
    }
  } catch (e) {
    console.log('[WARN] MQTT credentials: none (Supervisor MQTT service unavailable: ' + e.message + ')');
  }
} else {
  console.log('[INFO] MQTT credentials: from add-on options');
}
require('fs').writeFileSync('${CONFIG_PATH}', JSON.stringify(config, null, 2));
console.log('[INFO] Configuration loaded:');
console.log('[INFO]   MQTT broker: ' + config.mqtt.host + ':' + config.mqtt.port);
console.log('[INFO]   Z2M topic: ' + config.zigbee2mqtt_topic);
console.log('[INFO]   hue_native_control: ' + (config.hue_native_control !== 'unchanged' ? config.hue_native_control : '(not applied)'));
console.log('[INFO]   hue_power_on_behavior: ' + (config.hue_power_on_behavior !== 'unchanged' ? config.hue_power_on_behavior : '(not applied)'));
console.log('[INFO]   hue_power_on_brightness: ' + (config.hue_power_on_brightness || '(not applied)'));
console.log('[INFO]   hue_power_on_color_temperature: ' + (config.hue_power_on_color_temperature || '(not applied)'));
console.log('[INFO]   hue_power_on_color: ' + (config.hue_power_on_color || '(not applied)'));
console.log('[INFO]   Apply to groups: ' + (config.apply_to_groups ? 'yes' : 'no'));
console.log('[INFO]   Run interval: ' + config.run_interval);
console.log('[INFO]   Notifications: ' + (config.enable_notifications ? 'enabled' : 'disabled'));
console.log('[INFO]   Dry run: ' + (config.dry_run ? 'enabled' : 'disabled'));
console.log('[INFO]   Debug: ' + (config.debug ? 'enabled' : 'disabled'));
console.log('[INFO]   Devices: ' + (config.devices.length ? config.devices.join(', ') : 'ALL Hue devices (auto-discover)'));
})().catch((e) => { console.error('[ERROR] ' + e.message); process.exit(1); });
" || exit 1

# Run the applier
exec tsx /app/src/index.ts "${CONFIG_PATH}"
