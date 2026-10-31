# Arhitektura: kako DaisyDisk radi i kako to radi Diskbloom

> Napomena: ovo je *clean-room* analiza — zasnovana na javnoj dokumentaciji,
> ponasanju aplikacije koje se vidi spolja i opstem znanju o macOS API-jima.
> Binarni kod DaisyDisk-a nije dekompajliran (licenca to zabranjuje, a nije ni potrebno).

## 1. Arhitektura u 6 slojeva

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 1. Izbor diska          lista volumena, slobodno/zauzeto, purgeable  │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 2. Skener (engine)      paralelni obilazak FS-a, bulk metadata       │
 │                         ├─ getattrlistbulk() na macOS (1 syscall =   │
 │                         │   stotine unosa: ime, tip, alloc size, ino)│
 │                         ├─ privilegovani helper za "Scan as admin"   │
 │                         └─ hardlink dedup, ne prelazi mount-ove       │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 3. Model podataka       stablo cvorova u memoriji:                    │
 │                         {ime, alloc_size, broj_fajlova, deca[]}      │
 │                         + "Hidden space" = used(statfs) - suma(stablo)│
 │                         + "Purgeable"/APFS snapshot-i odvojeno       │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 4. Vizualizacija        sunburst (prstenovi = dubina, ugao = velicina)│
 │                         ├─ sitni cvorovi se spajaju u "smaller objects"│
 │                         ├─ boja po grani (hue), svetlina po dubini   │
 │                         └─ klik = zoom, hover = putanja + velicina   │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 5. Collector            "korpa" za brisanje: drag & drop cvorova,    │
 │                         ukupna velicina, brisanje tek na potvrdu     │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 6. Brisanje             Trash ili direktno; posle brisanja se stablo │
 │                         azurira lokalno (bez ponovnog skeniranja)    │
 └──────────────────────────────────────────────────────────────────────┘
```

## 2. Kljucni detalji koji prave razliku

| Problem | Sta DaisyDisk radi | Diskbloom |
|---|---|---|
| Brzina skeniranja | bulk syscall + vise niti, SSD voli paralelizam | `rayon` paralelni obilazak po direktorijumima |
| "Prava" velicina | alocirani blokovi, ne logicka duzina (sparse/kompresija) | `st_blocks * 512` |
| Hardlinkovi | broje se jednom | `(dev, ino)` set za fajlove sa `nlink > 1` |
| Mount-ovi | ne ulazi u druge volumene | poredi `st_dev` sa korenom (`--cross-fs` da se iskljuci) |
| Symlinkovi | ne prati | `symlink_metadata`, nikad ne prati |
| Nedostupni folderi | prikazuje kao "hidden space", nudi admin scan | broji greske, prijavljuje ih, nastavlja |
| Hiljade sitnih fajlova | grupise ih u "smaller objects" | isto, prag po uglu (`--min-angle`) |
| Bezbedno brisanje | Collector + potvrda | App: Collector + Trash. CLI: *dry-run* po defaultu, `--delete` + potvrda |
| Boot disk (APFS) | `/` je zapecaceni sistemski volumen | app skenira `/System/Volumes/Data` |
| Azuriranje posle brisanja | bez ponovnog skeniranja | `Tree::remove` oduzima velicinu od predaka |

## 3. Tok podataka

```
 root ──► scan (paralelno) ──► Node stablo ──┬─► top N tekst (terminal)
                                            ├─► HTML sunburst (samostalni fajl)
                                            └─► clean pravila ──► lista kandidata
                                                                    │
                                                    potvrda ◄───────┘
                                                       │
                                                  brisanje
```

## 4. Pravila za "cleaner" (sta se smatra smecem)

Kontekstualna pravila — ne samo po imenu, nego i po okolini (komsijama):

| Kategorija | Prepoznaje se kao | Uslov |
|---|---|---|
| Rust build | `target/` | sused `Cargo.toml` |
| Node deps | `node_modules/` | sused `package.json` |
| Python cache | `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/` | — |
| Gradle/Maven | `.gradle/`, `build/` | `build/` samo uz `build.gradle(.kts)` |
| Next.js / Nuxt | `.next/`, `.nuxt/` | sused `package.json` |
| Korisnicki kes | `~/.cache`, `~/Library/Caches` | — |
| Paketni kes | `~/.npm/_cacache`, `~/.cargo/registry/cache`, `~/.gradle/caches` | — |
| Xcode | `~/Library/Developer/Xcode/DerivedData` | — |
| Korpa | `~/.local/share/Trash`, `~/.Trash` | — |
| macOS smece | `.DS_Store` | — |

Sve kategorije su regenerisive (mogu se ponovo napraviti build-om / instalacijom).

## 5. Kako je Diskbloom organizovan

```
crates/core   diskbloom-core   skener, arena stablo (Tree), sunburst layout, clean pravila
crates/cli    bloom            terminal: top / map (HTML) / clean
crates/ffi    diskbloom-ffi    UniFFI: ScanJob + DiskTree objekti za Swift
macos/        Diskbloom.app    SwiftUI: sidebar volumena, Canvas sunburst, Collector, Smart Clean
```

Granica Rust ↔ Swift je namerno uska: Swift nikad ne dobija celo stablo,
samo ID-jeve i segmente koje trenutno crta (`DiskTree.layout`). Raspored
(uglovi, prstenovi, boje, "smaller objects") racuna Rust i pokriven je testovima.
