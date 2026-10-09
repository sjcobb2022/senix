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

1. immutable `/nix/store` overlay which is generated on `nixos-rebuild switch`
   similarly to `etc.overlay`.
2. patched nix distributable which adds metadata to derivations / NARs so we
   could attach rules via the metadata.
3. Maintain a set of overlays externally, which add a `passthru.selinux.roles`
   which define the roles for all outputs of a derivation. This would require
   most of nixpkgs pkgs to be ported over.
4. Hook into the nix cpp and use RegisterStoreImplementation to register a new
   store implementation which writes to the nix store and generates metadata
   matching some rules?
5. Custom FUSE filesystem. Control how xattrs are done.

The "most nix approach" I feel is option 1, since we can define rules. HOWEVER
this limits updating SELinux rules to build time. Meaning that a new derivation
created by nix build probably would not work that well. It MAY be triggered by a
post-build-hook in nix.conf for a global post build, but that feels tacky.

Option 1 would require storing the nix store in a new location, and pointing the
various daemon, GC and other nix store tools at it. It would also require an
overlayfs of built paths that iterates over the paths. This COULD be slow in nix
and therefore may require a fast application to determine all the paths and all
of their selinux settings. Not sure if SELinux has a tool for this.

Having a purely static image would not be too bad, as it would unconditionally
block new software and require administrator or privileged user access to
rebuild (whether local or remote). For users who have their devices controlled
for them (see [dawo](https://dawo.overheid-a.nl/),
[securix](https://github.com/cloud-gouv/securix)), I feel like this is a sane
approach. Because of SELinux' ability to lockdown so heavily, requiring a
restart may be the most feasible operation here. I believe this is similar to
how android operates with their selinux stuff.

### Comparison of custom store vs overlay

- Overlay
  - Can be constructed externally without any additional tooling.
  - Nix store needs to be moved, since an overlayfs would need to occupy the
    /nix/store location.
  - Not reactive to change, updating the nix store, such as using nix build,
    would not apply any new labels.
  - Would need a full rebuild for changes to occur.
  - Can be built as a (cacheable) derivation.
  - Lower (actual) store could be invalidated if a privileged process is able to
    modify the store. Potentially an example would be a sudo nix-collect-garbage
    or perhaps even a nix copy. I think it doesn't necessarily go through the
    daemon, but need to double check.
- Custom Store
  - Reactive to change, inherently labels and tags everything as it comes in or
    out.
  - /nix/store stays where it a custom store is most likely just an extension of
    LocalStore
  - Hard to construct externally, all the labeling would be done on client
    - Because of this it might be hard to get remote deployment working well.
  - If the store labels things on WRITE to the nix store:
    - The nix store would be left with potentially stale labels, since when a
      new image was deployed, most of the nix store has already been written and
      the new policies have not been activated.
  - If the store labels things on READ to the nix store:
    - Compute on client side.
    - Not really declarative, more a read-proxy for the store which acts
      dynamically based on some (potentially static) rules.
    - The policies which this reads from are the static part, actual reads are
      dynamic.
    - When deploying the new system, since we are referring to a local store,
      the new configuration will be evaluated with the previous generations
      rules. Therefore it could be outdated/softlock.

### Nice to haves with static image generation:

1. Tagging a parent directory
2. Path globbing ala
   `/usr/sbin/httpd(\.worker)?	--	system_u:object_r:httpd_exec_t:s`
3. Ability to overlay sparsely e.g. we still have access to everything in the
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
