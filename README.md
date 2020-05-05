# Strap: Bootstrap Your Machine with One Command

`strap` is a simple shell command designed to do one thing: 

Strap will take your machine from a starting state (for example, right after you buy it or receive it from your 
employer) and install and configure everything you want on your machine in a *single command*, in *one shot*.  Run 
`strap` and you can rest assured that your machine will have your favorite command line tools, system defaults, gui 
applications, and development tools installed and ready to go.

Strap was initially created to help newly-hired software engineers get up and running and
productive in *minutes* after they receive their machine instead of the hours or days it usually takes.  But Strap
isn't limited to software engineering needs - anyone can use Strap to install what they want - graphics software, 
office suites, web browsers, whatever.

<!-- 

## Watch It Run!

Here's a little `strap run` recording to whet your appetite for the things Strap can do for you:

[![asciicast](https://asciinema.org/a/188040.png)](https://asciinema.org/a/188040)

-->

## Overview

At the highest level:

**strap is a shell command that does the _bare minimum necessary_ to ensure 
[Ansible](https://docs.ansible.com/ansible/latest/index.html) is available and then immediately runs 
ansible to setup (aka 'converge') the local machine**.

In this sense, we're not reinventing the wheel - there are plenty of machine convergence tools out there already, and
it's best to just use one of them, like Ansible.

The only difference with strap is that strap covers the 'last mile' to obtain Ansible in a generic way that:

1. Ensures anyone can run it without knowing what Ansible is
1. Doesn't interfere with system or user-specific Ansible installations if there are any.
1. Ensures that the fastest way to remove it is to just delete the `~/.strap` directory.

As soon as Ansible is available, strap immediately delegates to it, automatically running one or more Ansible 
[playbooks](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) or 
[roles](https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html) on the local machine.

And we think that's pretty great - installing Ansible or Python is not always a trivial exercise, and we wanted to
ensure things 'just work', even if someone has never even heard of Python or Ansible.  It's so easy to use, anyone
can use it - from setting up a machine, or just installing things for a particular project, etc.

## Installation

To install strap, run the following on the command line:

```bash
curl -fsSL https://raw.githubusercontent.com/strapsh/strap/master/install | bash
source "$HOME/.strap/etc/straprc"
```

## Usage

Strap is a command line tool.  Assuming the strap installation's `bin` directory is in your `$PATH` as shown in the
installation instructions above, you can just type `strap --help` and see what happens:

```bash
me@myhost:~$ strap --help
strap version 0.3.6
usage: strap [options...] <command> [command_options...]
 
commands:
   help        Display help for a command
   run         Runs strap to ensure your machine is configured
   version     Display the version of strap
 
See `strap help <command>' for information on a specific command.
For full documentation, see: https://github.com/strapsh/strap
```

The `strap` command itself is quite simple - it basically loads some common environment settings and that's pretty 
much it. From there, it delegates most functionality to sub-commands, very similar to how the `git` command-line tool 
works.

## Strap Run

`strap run` ensures ansible is available and then immediately runs ansible to converge the local machine to a desired state.

This means that, even though one or more people can use `run strap` without knowing anything
about ansible (a great benefit to teams), at least one person needs to know how
to _write_ ansible "packages" that will be used during a strap run.  These "packages" in ansible's 
terminology are called _playbooks_ and _roles_.

Once a playbook or role is identified or available locally, strap makes running them that much easier.  You can run 
ansible playbooks and roles based on the directory where strap is run or by explicitly referencing them by id.

### Working Directory

If you just type `strap run` (without any arguments) in a working directory, and that directory has an ansible playbook 
available via the relative path:

```bash
.strap/ansible/playbooks/default/main.yml
```

then strap will run that playbook automatically.

It does the following steps in order:

1.  If a `.strap/ansible/playbooks/default/meta/requirements.yml` file exists that lists the 
    [playbook's role dependencies](https://galaxy.ansible.com/docs/using/installing.html#installing-multiple-roles-from-a-file),
    those requirements will be automatically downloaded first using the
    [ansible-galaxy command](https://docs.ansible.com/ansible/latest/cli/ansible-galaxy.html).
    
    **Strap enhancement**: Strap has a really nice feature that enables [transitive role dependency downloads](https://github.com/lhazlewood/ansible-galaxy-install):  if
    a dependency role is downloaded, and that role in turn has a `meta/requirements.yml` file, Strap will _automatically_
    transitively download _those_ dependencies that don't yet exist.  It will continue to walk the dependency tree, 
    downloading dependencies as necessary until all dependencies are resolved.
    
    Core ansible does not provide transitive resolution, but Strap does.

1. Strap will call the `ansible-playbook` command with the discovered playbook file targeting localhost/127.0.0.1.

### Specific Roles or Playbooks

If the working directory does not have a `.strap/ansible/playbooks/default/main.yml` playbook file, then you must
specify one or more roles or playbooks using the `--playbook` or `--role` arguments, i.e.

```bash
strap run [--playbook|--role] <id>
```

where `<id>` is an Ansible Galaxy identifier (i.e. `username.rolename`) or a GitHub url fragment that identifies the
role or playbook's git repository, (i.e. `username/repo`).

For example:

```bash
strap run --role geerlinguy.java
```

or

```bash
strap run --playbook example/foo
```


<!-- 

## Strap Packages

Strap is designed to have a lean core with most functionality coming from packages.  This section explains 
what packages are, how to use them, and how to write your own package(s) if you want to add or extend Strap 
functionality.

### What Is A Strap Package?

A Strap package is just a folder with bash scripts described by a `package.yml` file. 
This means Strap can access functionality from anywhere it can access a folder.  And because git repositories are 
folders, Strap can pull in functionality from anywhere it can access a git repository via a simple `git clone` command 
based on the package's unique identifier.

### Strap Package Identifier

A Strap Package Identifier is a string that uniquely identifies a Strap package.

The package identifier string format MUST adhere to the following definition:

    strap-package-id = group-id ":" package-name [":" package-version]
    
    group-id = "com.github." github-account-name
    
where
 * `github-account-name` equals a valid github username or organization name, for example `jsmith` or `strapsh`
 * `package-name` equals a git repository name within the specified github account, for example `cool-package`
 * `package-version`, if present, equals a git [refname](https://git-scm.com/docs/gitrevisions#gitrevisions-emltrefnamegtemegemmasterememheadsmasterememrefsheadsmasterem) that MUST be a tag, branch
    or commit sha that can be provided as an argument to `git checkout`.
    
A package release SHOULD always have a `package-version` string that conforms to the semantic version name scheme 
defined in the [Semantic Versioning 2.0.0 specification](https://semver.org/spec/v2.0.0.html).

Some examples:

 * `com.github.acme:hello:0.2.1`
 * `com.github.strapsh:cool-package:1.0.3`

> NOTE: we realize it is a rather constrictive requirement to have all packages hosted on github and conform to the
  specified location and naming scheme.  These restrictions will be relaxed when Strap's functionality
  is enhanced to support arbitrary repository locations (e.g. bitbucket, gitlab, Artifactory, etc).

#### Strap Package Resolution

How does Strap download a package based on the package identifier?

Consider the following Strap Package Identifier example:

    com.github.acme:hello:1.0.2
    
This tells strap to download the package source code obtained by (effectively) running:

```bash
git clone https://github.com/acme/hello
cd hello
git checkout tags/1.0.2
```

#### Strap Package Resolution Without `:package-version`
      
If there is not a `:package-version` suffix in a `strap-package-id`, a `:package-version` value of `:HEAD` will be 
assumed and the git repository's `origin/HEAD` will be used as the package source.

For example, consider the following Strap package id:

    com.github.acme:hello
    
This indicates the package source code will be obtained by (effectively) running:

```bash
git clone https://github.com/acme/hello

```
 
and no specific branch will be checked out (implying the default branch will be used, which is `master` in most cases).

> **WARNING**:
> 
> It is *strongly recommended to always specify a `:package-version` suffix* in every strap package idenfier to ensure
> deterministic (repeatable) behavior.  Omitting `:package-version` suffixes - and relying on the `:HEAD` default - 
> can cause errors or problems during a `strap` run. Omission can be useful while developing a package, but it is 
> recommended to provide a `:package-version` suffix at all other times.

### Strap Packages Directory

Any package referenced by you (or by other packages) that are not included in the Strap installation 
are automatically downloaded and stored in your `$HOME/.strap/packages` directory.

This directory is organized according to the following rules based on the Strap Package ID.  An example Strap
Package ID of `com.github.acme:hello:1.0.2` will be used for illustration purposes.

* The strap package id's `group-id` component is parsed, and period characters ( `.` ) are replaced with 
  forward-slash characters ( `/` ).  For example, the `group-id` of `com.github.acme` becomes `com/github/acme`

* The resulting string is appended with a forward-slash ( `/` ).  For example, `com/github/acme` becomes 
  `com/github/acme/`
  
* The resulting string is appended with the package id's `package-name` component.  For 
  example, `com/github/acme/` becomes `com/github/acme/hello`
  
* The resulting string is appended with a forward-slash ( `/` ).  For example, `com/github/acme/hello` becomes 
  `com/github/acme/hello/`

* The resulting string is appended with the `strap-package-id`'s `package-version` component if one exists, or `HEAD`
  if one doesn't exist.  For example:
  
  * A strap package id of `com.github.acme:hello:1.0.2` becomes `com/github/acme/hello/1.0.2` and
  * A strap package id of `com.github.acme:hello` becomes `com/github/acme/hello/HEAD`
  
* The resulting string is appended to the string `$HOME/.strap/packages/`.  For example,
  `com/github/acme/hello/1.0.2` becomes `$HOME/.strap/packages/com/github/acme/hello/1.0.2`

* The resulting string is used as the argument to the `mkdir -p` command, which is used to create the directory where 
  that package's code will be downloaded, for example:
  
  `mkdir -p "$HOME/.strap/packages/com/github/acme/hello/1.0.2"`


### Strap Package Structure

A strap package is a folder containing:

* A `META/package.yml` file
* Any number of bash scripts

Assuming `https://github.com/acme/hello` was a strap package repository, here is an example of what its directory 
structure might look like:

```
cmd/
    hello
hooks/
    run
lib/
    hello.sh
META/
    package.yml
```

The above tree shows the following:

* `META/package.yml` is a Strap package yaml file.  This file contains metadata about your package that Strap uses
  to ensure your package can be referenced by other packages, as well as enable any Strap sub-commands your package
  might provide, and more.

* `cmd/hello` is an executable script that can be executed as a strap sub-command.  That is, a strap user could
  type `strap hello` and strap would delegate execution to your `cmd/hello` script.  When committing this file to 
  source control, ensure that the file's executable flag is set, for example `chmod u+x cmd/hello`.

* `hooks/run` is an executable script that will execute when `strap run` is called. For example, if a strap user types
  `strap run` to kick off a run, strap will in turn invoke `hooks/run` as part of that execution phase.  Scripts in 
  the `hooks` directory must match exactly the name of the strap command being run.  Additionally, when committing 
  this file to source control, also ensure that the file's executable flag is set, for example `chmod u+x hooks/run`.

* `lib/hello.sh` is a bash script that may export shell variables and functions that can be sourced (used) by other 
  packages
  
  For example, if `lib/hello.sh` had a function definition like this:
  
      com::github::acme::hello() { 
        echo "hello"
      }
      
  other packages could *import* `hello.sh` and then they would be able to invoke `com::github::acme::hello` when they 
  wanted.
  
  We will cover how to import package library scripts soon.
  
 -->