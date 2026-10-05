# senix

Out of tree SELinux support for NixOS.

Taking the senix route.

Heavily inspired by RossTheComputerGuy's work and
[blog](https://tristanxr.com/post/selinux-on-nixos/) and various
[other](https://discourse.nixos.org/t/selinux-on-nixos/62729)
[discussions](https://github.com/NixOS/nix/pull/2670).

Made without the use of AI.

Current ideas to get support working:

1. mutable `/nix/store` overlay which allows for dynamic writing of selinux
   policies
2. immutable `/nix/store` overlay which is generated on `nixos-rebuild switch`
   similarly to `etc.overlay`.
3. patched nix distributable which adds metadata to derivations / NARs so we
   could attach rules via the metadata.
4. Maintain a set of overlays externally, which add a `passthru.selinux.roles`
   which define the roles for all outputs of a derivation. This would require
   most of nixpkgs to be ported over.
5. Just have an activation script which mounts the store in rw so that we can
   execute over the whole store.

The "most nix approach" I feel is option 2, since we can define rules. HOWEVER
this limits updating SELinux rules to build time. Meaning that a new derivation
created by nix build probably would not work that well. It MAY be triggered by a
post-build-hook in nix.conf for a global post build, but that feels tacky.

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

Nice to haves with static image generation:

1. Tagging a parent directory
2. Path globbing ala
   `/usr/sbin/httpd(\.worker)?	--	system_u:object_r:httpd_exec_t:s`
3. Directory based rule propogation e.g. `/nix/store` is assigned a
   `nix_store_t`
4. Ability to overlay sparsely e.g. we still have access to everything in the
   nix store, but the image just adds metadata to the paths that match the
   specified patterns.

Nix to haves in a nix module:

1. Some sort of DSL for defining rules
2. Some way to tag an entire derivation
3. Ability to create new selinux types, roles and users. (perhaps related to
   \#1)

Approaches to getting an overlay work

1. Write a small program to walk the nix store with the specified rules, and
   then create the overlay.
2. Find some sort of FS which handles the tagging easily via it's construction.
   May still require some scripting.

https://opensource.com/business/13/11/selinux-policy-guide
