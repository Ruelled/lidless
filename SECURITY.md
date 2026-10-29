# Security

## What Lidless can do

- **Root:** only `/usr/bin/pmset -a disablesleep 0` and `1`, through the sudoers
  rule in `/etc/sudoers.d/lidless`. The rule names your user and those two exact
  commands. Remove it in Settings > Lid, or with `sudo rm /etc/sudoers.d/lidless`.
- **Commands:** the `lidless` command line sends commands to the app as a
  distributed notification. Any process of your user can send one, and so can
  start or stop a session. A web page cannot. A session always keeps the user's
  heat limit as a ceiling.
- **Apps:** App Cleanup asks only the apps that you selected to quit.
- **Network:** one request a day to `api.github.com` for the update check. You
  can turn it off in Settings > General.
- **Files:** `~/Library/Application Support/Lidless/state.json`,
  `~/Library/Logs/Lidless/lidless.log`, `~/.local/bin/lidless`, and the skill
  files that you install in Settings > Agents.

## Report a problem

Use GitHub's private vulnerability reporting on this repository
(Security > Report a vulnerability). Do not open a public issue for a security problem.
