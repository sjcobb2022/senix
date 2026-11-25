{ pkgs, ... }:
let
  # This was written in a sleep deprived stupor. I have not even tested this.
  # This is basically the shape that I would want a custom cil renderer / DSL tho.
  cil = import ./cil.nix { inherit (pkgs) lib; };
  inherit (cil)
    type
    typeattributeset
    allow
    typetransition
    filecon
    portcon
    context
    class
    ;

  file = class "file";
  dir = class "dir";
  process = class "process";
  tcp_socket = class "tcp_socket";

  ctx =
    t:
    context "system_u" "object_r" t [
      [ "s0" ]
      [ "s0" ]
    ];
  fileExec = [
    "getattr"
    "open"
    "read"
    "execute"
  ];

  # a "macro" is just some nix code now.
  appendsLog = domain: logType: [
    (type logType)
    (typeattributeset "file_type" [ logType ])
    (allow domain logType (file [
      "getattr"
      "open"
      "append"
    ]))
    (allow domain logType (dir [
      "add_name"
      "write"
      "search"
    ]))
    (filecon "/var/log/myapp(/.*)?" "any" (ctx logType))
  ];
in
cil.mkModule {
  inherit pkgs;
  name = "myapp";
  rules = [
    (type "myapp_t")
    (type "myapp_exec_t")
    (type "myapp_port_t")
    (typeattributeset "domain" [ "myapp_t" ])
    (typeattributeset "exec_type" [ "myapp_exec_t" ])
    (typeattributeset "file_type" [ "myapp_exec_t" ])
    (typeattributeset "port_type" [ "myapp_port_t" ])

    # transition rules
    (allow "init_t" "myapp_exec_t" (file fileExec))
    (allow "init_t" "myapp_t" (process "transition"))
    (typetransition "init_t" "myapp_exec_t" "process" "myapp_t")
    (allow "myapp_t" "myapp_exec_t" (file (fileExec ++ [ "entrypoint" ])))

    (filecon "/usr/bin/myapp" "file" (ctx "myapp_exect_t"))
    (portcon "tcp" 8080 (ctx "myapp_port_t"))
    (allow "myapp_t" "myapp_port_t" (tcp_socket [ "name_bind" ]))

    # macro example
    (appendsLog "myapp_t" "myapp_log_t")

    # we can map things to an array
    (map
      (
        t:
        allow "myapp_t" t (file [
          "getattr"
          "open"
          "read"
        ])
      )
      [
        "etc_t"
        "usr_t"
      ]
    )
  ];
}
