# systemd Deployment

Choose either the continuous `quality-manager.service` or the timer-driven maintenance pair; do not enable both
against one coordinator database. Install the binary in `/usr/local/bin`, configuration in
`/etc/quality-manager/quality-manager.toml`, and the selected units in `/etc/systemd/system`.

Use absolute paths in the production configuration. Grant the `quality-manager` account only the project and
integration access required by policy. Adjust `ReadWritePaths` to the configured model_runner state and project
roots; the example permits `/var/lib/model-runner` and `/srv/quality-projects`. Then run `systemctl daemon-reload`
and enable either:

```text
systemctl enable --now quality-manager.service
systemctl enable --now quality-manager-maintenance.timer
```

Before deployment, run `quality-manager --config /etc/quality-manager/quality-manager.toml doctor`. Inspect activity
with `journalctl -u quality-manager.service` or `systemctl list-timers quality-manager-maintenance.timer`.
