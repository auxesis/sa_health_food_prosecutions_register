# Proxy

A simple proxy for scrapers running on Morph.

### A proxy for scrapers for broken websites

The `sa_health_food_prosecutions_register` scraper runs on [Morph](https://morph.io/auxesis/sa_health_food_prosecutions_register).

The scraper scrapes the [food prosecutions register](http://www.sahealth.sa.gov.au/wps/wcm/connect/public+content/sa+health+internet/about+us/legislation/food+legislation/food+prosecution+register) from the [SA Health website](http://sahealth.sa.gov.au/).

The SA health website sits behind some sort of Web Application Firewall. It's assumed this WAF blocks nasty requests to the website.

The WAF blocks legitimate requests from Morph, which means the scraper fails to run. The WAF sometimes returns a HTTP status code of 200 but with an error message in the body. Sometimes it just silently drops the TCP connection altogether. Not nice.

To make the scraper work on Morph, we can use [Tinyproxy](https://tinyproxy.github.io/) running on AWS to proxy requests from Morph to SA Health's website. The proxy is locked down to only accept requests originating from Morph.

### The scraper must explicitly use the proxy

On Morph, we set the `MORPH_PROXY` environment variable in the format `<host>:<port>`.

When the scraper runs, it detects if the `MORPH_PROXY` environment variable is set, and proxies all requests through it.

The scraper only emits that it's using a proxy – it doesn't emit the exact details of the proxy. Although access to the proxy service is locked down, it's best to not emit too much information about it.

### Designed to be cheap and resilient

The proxy service must be:

 - low cost
 - resilient to failure

To achieve this, we use AWS free tier, and autoscaling groups.

We ship [Terraform](https://terraform.io) config to automatically build out a proxy and supporting environment.

The Terraform config will:

 - Set up a single VPC, with a single public subnet, routing tables, and a single internet gateway.
 - Set up an ELB to publicly terminate requests, locked down with a security group to only accept requests from Morph.
 - Set up an autoscaling group of a single t2.micro (free tier) instance, with a launch config that boots the latest Ubuntu Xenial AMI, and links the ELB to the ASG.

## Setup the proxy

### You need Terraform and an IAM user

Ensure you have installed Terraform, at least at version 0.7.13.

There are a few things you need to configure on AWS before you can run Terraform:

 1. Create an IAM user. You should probably name it for the thing you're proxying (for example, `sa_health_food_prosecutions_register`).
 1. Attach `AmazonEC2FullAccess` and `AmazonVPCFullAccess` policies to IAM user)
 1. Create access keys for the IAM user.

### Drive changes with `make` and environment variables

Use the access keys you generated to export the `TF_VAR_aws_access_key` and `TF_VAR_aws_secret_key` environment variables:

```
export TF_VAR_aws_access_key='A***REMOVED***'
export TF_VAR_aws_secret_key='***REMOVED***'
```

Then to plan your changes:

```
make plan
```

To apply the plan:

```
make apply
```

To destroy the environment:

```
make destroy
```
