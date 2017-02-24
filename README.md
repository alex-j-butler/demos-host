# demos-host

A really simple [vibe.d](https://vibed.org) application for hosting demo files
recorded on ozfortress servers.

Relies on [ssc](https://github.com/ozfortress/ssc) for actually running the
servers.

Demo files are saved in `public/demos/<client>/<user>/`.
`<user>` is a lower-case RFC 4648 string

## Dependencies

Requires [D](https://dlang.org) and [dmd](https://code.dlang.org).

## Building

Build and run using `dub run`.

## Deploying

We use [capistrano](https://github.com/capistrano/capistrano) for deploying.

Run `cap production deploy` to deploy.
