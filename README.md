Continous Integration server for YunoHost apps
==============================================

This repo manages the interface between [yunorunner](https://github.com/YunoHost/yunorunner) (the CI web UI / scheduler) and [package_check](https://github.com/YunoHost/package_check) (the test suite).

`CI_package_check` is likely to be entirely merged in yunorunner, but still exists for historical reasons.

It consists essentially in : 

- `analyseCI.sh`, which is the "actual job" called by yunorunner.

CI_package_check currently also handles a bunch of things like the `!testme` webhook, XMPP notification, some badges, updating app levels, etc.
