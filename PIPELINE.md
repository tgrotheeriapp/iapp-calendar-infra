## Pipeline Files
All the files required for the pipeline configuraiton (property files) are located in the `.iapp` directory in the main directory of the repository.

```
.iapp [pipeline directory]
 |-- manifest.yaml [The main property file that defines the pipeline settings and the product catalog metadata]
 |-- master.yaml [The property file for the root aws account, (e.g: masster)]
 |-- {branch}.yaml [The property file for the specific aws account, (e.g: sandbox-nonprod)]
```

#### manifest.yaml format
```
pipeline:
  type: cft
  # (Optional) The directory path (within repo) where to start from for the build [default = cloudformation]
  build_dir: cloudformation
  # (Optional) The path to the build file to override the default build file
  build_file:
# Metadata information about the resource
catalog:
  # (Required) The name of the organization that is responsible for managing the product (iapp unless managed by a 3rd party)
  organization: iapp
  # (Required) The name of the portfolio that identifies its products, applications, and components
  portfolio: cicd
  # (Required) The name of the product that identifies its applications and components
  product: pipeline
  # (Required) The name of the application (or service module) that identifies its components
  application: pipeline
  # (Optional) The name of the component that aligns with the application or service module
  component: infra
  # (Required) The name of the department that owns the resource
  department: tech
  # (Optional) The email address of the support team to contact
  support_email: pipeline-support@iapp.org
code:
  # (Required) The location (url) where to find the source code
  sourcecode_url: https://github.com/PrivacyAssociation/cft-project
# (Optional) A list (array) of template files (including extension) to build and deploy in the order specified
queue:
  - template3.yaml
  - template1.yaml
  - template2.yaml
```

#### {branch}.yaml format
```
pipeline:
  release_lvl: alpha
  release_vrs: v0.0.1
aws:
  # (Required) The AWS region to use
  region: us-east-1
  # (Required) The number of the AWS Account to use (e.g.: us-east-1)
  account: xxxxxxxxxx
  # (Required) The name of the environment to use
  environment: development
  # (Required) The name of the domain, (e.g.: iapp-calendar-api). Leave blank if no custom domain name is needed.
  domain: ''  
  # (Optional) The AWS arn of the certificate used by the api. Must be provided if the domain name is set
  certarn: arn:aws:acm:us-east-1:xxxxxxxxxxxxx:certificate/yyyyyyyy-yyyyyyyyyyyyy-yyyyyyyyyy
```