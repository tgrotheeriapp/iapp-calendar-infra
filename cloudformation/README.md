# Modules

The following modules are to deployed in the following order:

### application-iapp-calendar
Performs the default steps to setup the application, (registration, secret, etc).
> NOTE: Make sure to rename the CFT based on your applicaiton name.
> + .iapp/manifest.yaml
> + cloudformation/application-iapp-calendar.yaml
> + cloudformation/application-iapp-calendar.md

Template: [application-iapp-calendar](./application-iapp-calendar.md)

### Example Calling Custom Resources
Provides an example Stack that call custom resources to reference networking resources, (e.g.: VPN, Subnet, Security Group).

Template: [application-iapp-calendar-template](./application-iapp-calendar-template.md)