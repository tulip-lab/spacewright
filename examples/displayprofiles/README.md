# Optional displayplacer integration

SpaceWright looks for three executable Fish commands under
`SPACEWRIGHT_DISPLAY_PROFILES_ROOT`:

- `display-solo-primary.fish`
- `display-primary-plus-wide-left.fish`
- `display-primary-plus-tall-left.fish`

Each command should run the machine-specific `displayplacer` invocation for
that profile and return its status. Keep display UUIDs and generated commands
in the consumer configuration repository, not in SpaceWright.

Example shape:

```fish
#!/usr/bin/env fish
displayplacer '<your machine-specific profile here>'
```

Then set:

```fish
set -gx SPACEWRIGHT_DISPLAY_PROFILES_ROOT ~/.config/displayprofiles
```

Do not copy UUIDs between Macs; regenerate each profile locally.
