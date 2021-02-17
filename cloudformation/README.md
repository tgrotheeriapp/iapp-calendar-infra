# Modules

The following modules are to deployed in the following order:

### iapp-calendar-app
Performs the default steps to setup the application, (registration, secret, etc).
> NOTE: Make sure to rename the CFT based on your applicaiton name.
> + .iapp/manifest.yaml
> + cloudformation/iapp-calendar-app.yaml
> + cloudformation/iapp-calendar-app.md

Template: [iapp-calendar-app](./iapp-calendar-app.md)

### Example Calling Custom Resources
Provides an example Stack that call custom resources to reference networking resources, (e.g.: VPN, Subnet, Security Group).

Template: [iapp-calendar-app-template](./iapp-calendar-app-template.md)