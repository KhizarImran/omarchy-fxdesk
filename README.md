# FX Desk

An Omarchy bar widget for FX traders: which sessions are open right now, when
the next one turns over, and every major G10 release due today.

The bar pill reads `LDN+NY · USD 28m` — the sessions currently open, and the
next release with its countdown when one is due within twelve hours. Click it
for the panel: a dot-matrix world map with the four centres lighting up as they
open, today's session windows laid against a local midnight-to-midnight strip
with a line on now, then the session countdowns and today's releases.

Each release carries an impact dot — red for high (payrolls, CPI, rate
decisions), amber for medium, grey for low — followed by the forecast (`f`) and
the previous print (`p`). Those three hues are fixed rather than themed: red has
to mean the same thing on every colour scheme. Everything else follows the
Omarchy theme.

## Data

The map is Natural Earth 110m land (public domain), rasterised once to a 120x45
grid and baked into `LandMask.js`. It is drawn on a `Canvas`, so a repaint is
one pass of a few hundred arcs rather than thousands of QML items, and it only
repaints while the panel is open.

Sessions are computed locally from `zoneinfo`, so London and New York follow
their own DST rather than a fixed UTC offset. Weekends have no window.

The calendar is the Forex Factory weekly feed
(`nfs.faireconomy.media/ff_calendar_thisweek.json`), cached under
`~/.cache/omarchy-fxdesk/` and refetched hourly. The feed rate limits, so a
manual refresh (`r` in the panel) still keeps a five-minute floor under it.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Currencies | `USD,EUR,JPY,GBP,CHF,AUD,NZD,CAD` | Which currencies' releases to list |
| Impact | `High + Medium` | How major a release has to be to appear |
| Refresh interval | `60` minutes | How often the feed is refetched |

Session hours are the one thing without a settings surface: they are the
`SESSIONS` table at the top of `bin/fx-brief`, which is a one-line edit if your
desk calls Sydney 07:00–16:00 rather than 08:00–17:00.

## Development

`bin/fx-brief` is runnable on its own and prints everything the widget draws:

```bash
bin/fx-brief --ccy USD,EUR --impact High | jq
test/fx-brief-test.sh
```

## Install

```bash
omarchy plugin add https://github.com/KhizarImran/omarchy-fxdesk --enable
```

That clones it into `~/.config/omarchy/plugins/khizarimran.fxdesk/` and puts the
pill in your bar. Move it with `omarchy bar move khizarimran.fxdesk --section
right`, and change currencies, impact and refresh interval in the widget's
settings.

Update later with `omarchy plugin update khizarimran.fxdesk`.

## Remove

```bash
omarchy plugin remove khizarimran.fxdesk
rm -rf ~/.cache/omarchy-fxdesk
```

The plugin writes nothing else: no config outside its own widget settings, no
files in your home beyond that one cache directory.

## Dependencies

`python3` (standard library only — `zoneinfo`, `urllib`) and network access to
`nfs.faireconomy.media` for the calendar. Nothing else, and nothing is
installed for you.

## Author

FX Desk by [@khzrimrn](https://github.com/KhizarImran). MIT licensed.
