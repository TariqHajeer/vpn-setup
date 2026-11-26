// VPN Status: shows the names of the WireGuard VPNs that are up (their names in
// /etc/vpn/vpns, as NetworkManager knows them) in the top-bar system pill, plus
// "⚠ kill switch off" while /etc/vpn/killswitch-off exists. See ~/vpn-setup/MANUAL.md.
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import NM from 'gi://NM';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';

const KILLSWITCH_OFF_FLAG = '/etc/vpn/killswitch-off';
const REFRESH_SECONDS = 3;

const VpnStatusIndicator = GObject.registerClass(
class VpnStatusIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();
        this._label = new St.Label({
            style_class: 'vpn-status-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._label);
        this.visible = false;
    }

    update(names, killswitchOff) {
        const parts = [];
        if (names.length > 0)
            parts.push(names.join(' · '));
        if (killswitchOff)
            parts.push('⚠ kill switch off');
        this._label.text = parts.join('   ');
        this.visible = parts.length > 0;
        if (killswitchOff)
            this._label.add_style_class_name('vpn-status-warning');
        else
            this._label.remove_style_class_name('vpn-status-warning');
    }
});

export default class VpnStatusExtension extends Extension {
    enable() {
        this._indicator = new VpnStatusIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);

        this._cancellable = new Gio.Cancellable();
        NM.Client.new_async(this._cancellable, (_source, result) => {
            try {
                this._client = NM.Client.new_finish(result);
            } catch (e) {
                if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    console.error(`vpn-status: can't reach NetworkManager: ${e.message}`);
                return;
            }
            this._refresh();
        });

        this._refresh();
        this._timerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _activeVpnNames() {
        if (!this._client)
            return [];
        return this._client.get_active_connections()
            .filter(ac => ac.get_connection_type() === 'wireguard' &&
                          ac.get_state() === NM.ActiveConnectionState.ACTIVATED)
            .map(ac => ac.get_id())
            .sort((a, b) => a.localeCompare(b));
    }

    _refresh() {
        const killswitchOff = GLib.file_test(KILLSWITCH_OFF_FLAG, GLib.FileTest.EXISTS);
        this._indicator?.update(this._activeVpnNames(), killswitchOff);
    }

    disable() {
        this._cancellable?.cancel();
        this._cancellable = null;
        if (this._timerId) {
            GLib.source_remove(this._timerId);
            this._timerId = null;
        }
        this._client = null;
        this._indicator?.destroy();
        this._indicator = null;
    }
}
