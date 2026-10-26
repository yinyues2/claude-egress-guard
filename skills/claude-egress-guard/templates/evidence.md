# Deployment record

Fill this in once, keep it next to the deployment (not in the repository, not in
a public note). Six months later it is the only thing that explains an incident.

```
host            :
operator        :
date (UTC)      :

os              :
kernel          :
systemd         :
memory / swap   :
disk free       :

proxy endpoint  :          # credentials stripped, e.g. http://127.0.0.1:1080
proxy unit      :          # systemctl unit that keeps it alive
proxy enabled   : yes / no # systemctl is-enabled
exit address    :
exit country    :
exit observed   :          # three probes, timestamped

install method  : vendor / npm / package
claude version  :
gated paths     :          # /usr/local/bin/claude, /usr/bin/claude, ~/.local/bin/claude

policy file     : /etc/claude-egress-guard.conf
expected ip     :
allowed cidrs   :
strict net      : on / off
log refusals    : on / off

verify          : __ PASS / __ FAIL (deep: yes/no)
drill           : refused with proxy down = yes/no, recovered after = __ s
first prompt    : ok / failed

known deviations:
notes           :
```

## Change log

One line per policy change: date, what changed, why.

```
YYYY-MM-DD  EXPECTED_IP 203.0.113.10 -> 198.51.100.7   proxy rotated, provider notice
```
