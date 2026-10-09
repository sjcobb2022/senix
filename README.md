# senix

Out of tree SELinux support for NixOS.

Taking the senix route.

Heavily inspired by RossTheComputerGuy's work and
[blog](https://tristanxr.com/post/selinux-on-nixos/) and various
[other](https://discourse.nixos.org/t/selinux-on-nixos/62729)
[discussions](https://github.com/NixOS/nix/pull/2670).

Made without the use of AI.

## Plans

Current ideas to get support working:

1. mutable `/nix/store` overlay which allows for dynamic writing of selinux
   policies
2. immutable `/nix/store` overlay which is generated on `nixos-rebuild switch`
   similarly to `etc.overlay`.
3. patched nix distributable which adds metadata to derivations / NARs so we
   could attach rules via the metadata.
4. Maintain a set of overlays externally, which add a `passthru.selinux.roles`
   which define the roles for all outputs of a derivation. This would require
   most of nixpkgs pkgs to be ported over.
5. Just have an activation script which mounts the store in rw (if possible) so
   that we can execute over the whole store.
6. Hook into the nix cpp and use RegisterStoreImplementation to register a new
   store implementation which writes to the nix store and generates metadata
   matching some rules?
7. Just write a big nix_store_t over the store on mount, and add transition
   rules from that to the other domains.

The "most nix approach" I feel is option 2, since we can define rules. HOWEVER
this limits updating SELinux rules to build time. Meaning that a new derivation
created by nix build probably would not work that well. It MAY be triggered by a
post-build-hook in nix.conf for a global post build, but that feels tacky.

Option 2 would require storing the nix store in a new location, and pointing the
various daemon, GC and other nix store tools at it. It would also require an
overlayfs of built paths that iterates over the paths. This COULD be slow in nix
and therefore may require a fast application to determine all the paths and all
of their selinux settings. Not sure if SELinux has a tool for this.

I am currently more in favour of building a static image which lays out the
structure of the nix store. We can control the generation of these paths. If we
can get the image to propagate patterns downwards, or act somewhat dynamically
that would be nice.

Writing an activation script which just applies a bunch of policy stuff to the
files is less "pure", but it would get the job done. However if there it could
break integrity checks perhaps? Would need to test that.

Having a purely static image would not be too bad, as it would unconditionally
block new software and require administrator or privileged user access to
rebuild (whether local or remote). For users who have their devices controlled
for them (see [dawo](https://dawo.overheid-a.nl/),
[securix](https://github.com/cloud-gouv/securix)), I feel like this is a sane
approach. Because of SELinux' ability to lockdown so heavily, requiring a
restart may be the most feasible operation here. I believe this is similar to
how android operates with their selinux stuff.

Having a truly immutable overlay store would ensure that

### Nice to haves with static image generation:

1. Tagging a parent directory
2. Path globbing ala
   `/usr/sbin/httpd(\.worker)?	--	system_u:object_r:httpd_exec_t:s`
3. Directory based rule propogation e.g. `/nix/store` is assigned a
   `nix_store_t`
4. Ability to overlay sparsely e.g. we still have access to everything in the
   nix store, but the image just adds metadata to the paths that match the
   specified patterns.

### Nix to haves in a nix module:

1. Some sort of DSL for defining rules
2. Some way to tag an entire derivation
3. Ability to create new selinux types, roles and users. (perhaps related to
   \#1)

### Approaches to getting an overlay work

1. Write a small program to walk the nix store with the specified rules, and
   then create the overlay.
2. Find some sort of FS which handles the tagging easily via it's construction.
   May still require some scripting.

## Extras

https://opensource.com/business/13/11/selinux-policy-guide

### secil / nix dsl

This is not necessarily a priority, and could in fact be provided in another
flake, or something external. However, since SELinux
[CIL](https://github.com/SELinuxProject/selinux/tree/main/secilc) is basically a
functional language, we could quite easily create a nix wrapper which generates
this from some syntax tree.

If we have issues executing cil, we can still then render it to whatever
structure we need to get it to work.

Given that CIL is an intermediary format, we could use this to either format
written rules as "regular" file_contexts.local, or format the CIL intermediary
to CIL, and then compile it.

## who is this for?

- Securing a system for users
  - Home users
    - The minority of home users will even think of security.
    - A home user will most likely want somewhat lax rules if using selinux.
    - A home user will access many files and have many applications.
      - Having many applications would require malleable rules, or a large
        quantity of rules.
    - Configuration and software may change frequently.
    - Has control over their own configuration.

  - Enterprise users
    - If working security focused enterprise, things can move slow.
    - Different organisational roles require different restrictions on device
      mutability.
      - Someone in a more management-focused position would probably be fine
        with a locked down system which has a browser and some bespoke
        organisation-specific software perhaps.
      - A tech related role would need some more flexibility
    - Wants to avoid data loss / getting compromised, although depending on the
      scope of the user this may not be too big a deal. (with proper
      organisation silos)
    - Does not have control over their own system (often depends on size of the
      org)
    - May have a standard suite of software (or not) for employees to use.

  - Government users
    - Require a strict data security practices
    - Does not want to get hacked at all costs
      - May have sensitive data
      - Has a responsibility to protect data
    - Government may have goal to move towards sovereign tech (see securix +
      dawo)
    - Once again, may have widely different organisation roles.
    - Definitely does not (should not?) have control over their own systems.
    - May have a standard suite of software for workers to use

- Securing a system for deployment
  - Servers
    - Bare metal servers that run exposed (or semi-exposed for local
      deployments) software greatly benefit from additional MAC.
    - Only ever changes on software update/redeployment so requires redeploy.
  - Docker images
    - It may still be pertinent for some organisations to run SELinux in docker,
      as there still may be some artefacts produced by software which may be
      valuable to an attacker.
    - Can benefit exceptionally from MAC by reducing attack surface.
    - Redeployment often redeploys a new image, and therefore massively static.

Catering towards the more static aspects of servers and users, is easier, as
less dynamic script are required. Therefore, enterprise/government users and
deployable systems are the core target for this. We can play into their
staticness to some degree here, so that we don't need a boatload of dynamic
scripts.

This leads to the conclusion that option 2 from the plans section is most likely
the best approach still.

One further point that this raises is that for enterprise and governmental
bodies, deployment of a configuration is often not done on-device. It would
probably be done remotely. Therefore, it is appropriate to require an approach
which can be remotely deployed. Local change to the filesystem does not meet the
reproducible requirements that we set out to achieve.

## Additional things to patch

Reference table in
https://wiki.archlinux.org/title/SELinux#Current_status_in_Arch_Linux for list
of pkgs which need to be compiled with selinux enabled.

List of packages that need selinux support.

- coreutils
- cronie
- dbus
- findutils
- iproute2
- openssh
- pam
- pambase
- psmisc
- shadow
- sudo
- systemd
- util-linux
- uutils-coreutils
