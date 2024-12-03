# xOTA

xOTA is a platform to host temporary amateur radio activies that have similar mechanics as Islands on the Air (IOTA) or Parks on the Air (POTA).
It has been used the first time at 37C3 in Hamburg in December 2023 as Toilets on the Air (TOTA).


## Setup Server on Uberspace
This section describes the setup that was used for TOTA at 37C3.
We used uberspace.de as a hoster and the instructions are geared towards hosting it on uberspace.

Create an uberspace account and follow the [manual](https://manual.uberspace.de) to SSH in.

### Install Swift
```
wget https://download.swift.org/swift-5.9.2-release/centos7/swift-5.9.2-RELEASE/swift-5.9.2-RELEASE-centos7.tar.gz
mkdir Swift
cd Swift/
tar xzf ../swift-5.9.2-RELEASE-centos7.tar.gz
ln -s ~/Swift/swift-5.9.2-RELEASE-centos7/usr/bin/swift ~/bin/swift
```

Create a file at `~/Swift/fixincludes/unistd.h` with the following contents:
```
#define HAS_PROBLEMATIC_UNISTD_H 1
// Below code is from https://github.com/nickhutchinson/libdispatch/blob/e1778632982b32e5156de888e54920d7ac848178/fixincludes/unistd.h

#ifndef DISPATCH_FIXINCLUDES_UNISTD_H_
#define DISPATCH_FIXINCLUDES_UNISTD_H_
/* The use of __block in some unistd.h files causes Clang to report an error.
 * We work around the issue by forcibly undefining __block. See
 * https://bugzilla.redhat.com/show_bug.cgi?id=1009623 */

#if HAS_PROBLEMATIC_UNISTD_H
#pragma push_macro("__block")
#undef __block
#define __block my__block
#include_next <unistd.h>
#pragma pop_macro("__block")
#else
#include_next <unistd.h>
#endif

#endif // DISPATCH_FIXINCLUDES_UNISTD_H_
```

### Build the project
Clone xOTA to your host, `cd` into the path and run:
```
swift build --configuration release -Xcc -I../Swift/fixincludes/
```

### Migrate DB
```
.build/release/xOTA_App --env configure  migrate
```

### Configure supervisord

Create `~/etc/services.d/tota-prod.ini` with entried adjusted for your setup:
```
[program:tota-prod]
command=/home/tota2023/xOTA-prod/.build/release/xOTA_App serve --env production -p 8081 -H 0.0.0.0
directory=/home/tota2023/xOTA-prod/
startsecs=10
environment=CCCHUB_DOMAIN="events.ccc.de/congress/2023/hub/sso/",CCCHUB_CLIENT_ID="<redacted>",CCCHUB_CLIENT_SECRET="<redacted>",CCCHUB_AUTH_CALLBACK="https://2023.totawatch.de/ccc-hub-auth-complete",
stdout_logfile=/home/tota2023/logs/tota-prod/stdout.log
stderr_logfile=/home/tota2023/logs/tota-prod/stderr.log
```

Load and launcht the service:
```
supervisorctl reread
supervisorctl update
supervisorctl start tota-prod
```

Read the [uberspace manual](https://manual.uberspace.de/daemons-supervisord/) for more instructions.

### Configure domain

Read the uberspace manuals on [adding domains](https://manual.uberspace.de/web-domains/) and configuring [web backends](https://manual.uberspace.de/web-backends/) to run point to the Swift server port.

## Configure xOTA for your Activity Program

The naming theme of programs can be changed in `configure.swift`.
The [Leaf](https://docs.vapor.codes/leaf/overview/) templates are in `Resources/Views/` and need to be adjusted for your needs.

There is an admin interface available at /admin to create and update references and reset user passwords.
To make a user admin use `.build/release/App --env configure admin -c <CALLSIGN>`, then user can then access the admin interface.


### Authentification option
There is CCC Hub SSO authentification as well as username + password authentification available as options.

Which authentification options are enabled can be configured in `configure.swift`.

Authentification is tied to the hub SSO endpoint that was reachable at `events.ccc.de/congress/2023/hub/sso/`. For future CCC events, the SSO endpoint needs to be adjusted in the environment and `CCCHubAuthController.swift`.

Create an OAuth app in the CCC Hub Backoffice with Client type = Confidential, Authorization grant type = Authorization Code.

