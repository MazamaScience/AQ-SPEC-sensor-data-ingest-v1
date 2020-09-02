# Digital Ocean Primer

[Digital Ocean](http://digitalocean.com/) (DO) is a cloud service provider similar
to Amazaon Web Services (AWS), Microsoft Azure or Google Cloud. Digital Ocean is 
more focused  on Unix systems and the needs of developers. 

The [analogsea](https://analogsea.icu) package provides a client for the DO API 
and has excellent instructions for getting started. Using **analogsea** allows
you to create R scripts that do all of the setup and teardown of DO instances
which are known as "droplets".

Another source of instructions for those comfortable at the Unix command line is
Jon's [DigitalOcean-R-setup](https://github.com/jonathancallahan/DigitalOcean-R-setup)
repository.

## Set up an account

Follow the instructions at https://analogsea.icu/#create-a-do-account

Make sure to set up ssh keys and a Personal Access Token

## Spin up a droplet

At the R console, you will want to create a droplet with ssh keys like this:

```
> keys()
$jonathan_at_tahoma
  ...
> droplet_create(ssh_keys = "jonathan_at_tahoma")
NB: This costs $0.00744 / hour until you droplet_delete() it
Waiting for create ..............
<droplet>SufferingMatrix (200863084)
  IP:        droplet likely not up yet
  Status:    new
  Region:    San Francisco 2
  Image:     18.04.3 (LTS) x64
  Size:      s-1vcpu-1gb
  Volumes:   
> d1 <- droplet(200863084)
> d1 %>% summary()
<droplet_detail>SufferingMatrix (200863084)
  Status: active
  Region: San Francisco 2
  Image: 18.04.3 (LTS) x64
  Size: s-1vcpu-1gb ($0.00744 / hr)
  Estimated cost ($): 0
  Locked: FALSE
  Created at: 2020-07-21T11:46:50Z UTC
  Networks: 
     v4: ip_address (64.225.119.77), netmask (255.255.240.0), gateway (64.225.112.1), type (public)
     v6: none
  Kernel:   
  Snapshots:  
  Backups:  
  Tags:   
```

## Log in as root

Using the IP address `64.225.119.77` you can log in with:

```
ssh root@64.225.119.77
Welcome to Ubuntu 18.04.3 LTS (GNU/Linux 4.15.0-66-generic x86_64)
...
```

## Install core software

Now that you are logged in as root you can follow the instructions at
https://github.com/jonathancallahan/DigitalOcean-R-setup#instructions

