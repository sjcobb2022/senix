{ lib, ... }:
# Hopefully a super minimal sexp parser for cil (which is a sexp language)
# Include as well some helper functions which
let
  sexp =
    x:
    # terminal symbols
    if builtins.isString x then
      x
    else if builtins.isInt x then
      x
    # non-terminal list
    else if builtins.isList x then
      "(" + lib.concatStringsSep " " (map sexp x) + ")"
    # terminal unreadable type
    else
      throw "cannot render value of type ${builtins.typeOf x}";

  # just flatten with newlines
  # Should we add newline at end? idk
  render = rules: lib.concatStringsSep "\n" (lib.flatten rules) + "\n";

  # cil string literal
  str = s: "\"${s}\"";

  # a generic statement type
  stmt = keyword: args: sexp ([ keyword ] ++ args);

  # cil builtins
  type = name: stmt "type" [ name ];
  typeattribute = name: stmt "typeattribute" [ name ];
  typeattributeset =
    attr: members:
    stmt "typeattributeset" [
      attr
      members
    ];
  role = name: stmt "role" [ name ];
  roletype =
    r: t:
    stmt "roletype" [
      r
      t
    ];

  # allow intrinsics
  allow =
    src: tgt: perms:
    stmt "allow" [
      src
      tgt
      perms
    ];
  dontaudit =
    src: tgt: perms:
    stmt "dontaudit" [
      src
      tgt
      perms
    ];
  auditallow =
    src: tgt: perms:
    stmt "auditallow" [
      src
      tgt
      perms
    ];
  neverallow =
    src: tgt: perms:
    stmt "neverallow" [
      src
      tgt
      perms
    ];

  # transitions
  typetransition =
    src: tgt: cls: result:
    stmt "typetransition" [
      src
      tgt
      cls
      result
    ];

  # file contexts and port contexts
  filecon =
    path: kind: context:
    stmt "filecon" [
      (str path)
      kind
      context
    ];
  portcon =
    proto: port: context:
    stmt "portcon" [
      proto
      port
      context
    ];

  # helpful for class stuff
  class = name: perms: [
    name
    perms
  ];

  # easy context creator
  context = user: role: type: range: [
    user
    role
    type
    range
  ];

  mkModule =
    {
      pkgs,
      name,
      rules,
    }:
    let
      text = render rules;
      cil = pkgs.writeText "${name}.cil" text;
    in
    {
      inherit text cil;
    };
in
{
  inherit
    sexp
    render
    str
    stmt
    mkModule
    type
    typeattribute
    typeattributeset
    role
    roletype
    allow
    dontaudit
    auditallow
    neverallow
    typetransition
    filecon
    portcon
    class
    context
    ;
}
