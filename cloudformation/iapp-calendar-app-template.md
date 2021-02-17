# iapp-calendar-app-template.yaml

## Resource Types
+ [Custom::String](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-cfn-customresource.html)


## Template Parameters
| Parameter                 | Type    | Description                                                                                                 |
| ------------------------- | ------- | ----------------------------------------------------------------------------------------------------------- |
| pOrganization             | String  | The name of the portfolio that identifies its products, applications, and components                        | 
| pPortfolio                | String  | The name of the portfolio that identifies its products, applications, and components                        |
| pProduct                  | String  | The name of the product that identifies its applications and components                                     |
| pApplication              | String  | The name of the application (or service module) that identifies its components                              |
| pComponent                | String  | The name of the component that aligns with the application or service module                                |
| pDepartment               | String  | The name of the department that owns the resource                                                           |
| pEnvironment              | String  | The name of the environment in which the resource is running (e.g.: sandbox, development, test, production) |
| pSupportEmail             | String  | The email address of the support team to contact                                                            |
| pSourceCodeURL            | String  | The location where the source code resides                                                                  |

## Exports
| Name                                                     | Description                                     |
| -------------------------------------------------------- | ----------------------------------------------- |

## Further Reading
