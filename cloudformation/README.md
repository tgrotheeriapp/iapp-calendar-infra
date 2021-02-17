# Modules

The following modules are to deployed in the following order:

### application-myapp
Performs the default steps to setup the application, (registration, secret, etc).
> NOTE: Make sure to rename the CFT based on your applicaiton name.
> + .iapp/manifest.yaml
> + cloudformation/application-myapp.yaml
> + cloudformation/application-myapp.md

Template: [application-myapp](./application-myapp.md)

### Example Calling Custom Resources
Provides an example Stack that call custom resources to reference networking resources, (e.g.: VPN, Subnet, Security Group).

Template: [myapp-template](./myapp-template.md)