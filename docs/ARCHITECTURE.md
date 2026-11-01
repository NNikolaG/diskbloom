# Arhitektura Diskbloom-a

Ovaj dokument opisuje kako Diskbloom skenira disk, kako cuva i prikazuje rezultat
i zasto su kljucne odluke donete bas tako.

## 1. Arhitektura u 6 slojeva

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 1. Izbor diska          lista volumena, slobodno/zauzeto, purgeable  │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 2. Skener (Rust)        paralelni obilazak FS-a (rayon)              │
 │                         ├─ lstat za svaki unos: tip, alloc size, ino │
 │                         ├─ boot disk preko /System/Volumes/Data      │
 │                         └─ hardlink dedup, ne prelazi mount-ove       │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 3. Model podataka       stablo cvorova u memoriji:                    │
 │                         {ime, alloc_size, broj_fajlova, deca[]}      │
 │                         + "Hidden space" = used(statfs) - suma(stablo)│
 │                         + purgeable i Time Machine snapshot-i        │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 4. Vizualizacija        sunburst (prstenovi = dubina, ugao = velicina)│
 │                         ├─ sitni cvorovi se spajaju u "smaller objects"│
 │                         ├─ boja po grani (hue), svetlina po dubini   │
 │                         └─ klik = zoom, hover = putanja + velicina   │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 5. Collector            "korpa" za brisanje: drag & drop cvorova,    │
 │                         ukupna velicina, brisanje tek na potvrdu     │
 ├──────────────────────────────────────────────────────────────────────┤
 │ 6. Brisanje             u Trash (simctl / tmutil gde treba); stablo │
 │                         azurira lokalno (bez ponovnog skeniranja)    │
 └──────────────────────────────────────────────────────────────────────┘
```

## 2. Kljucni detalji koji prave razliku

| Problem | Resenje u Diskbloom-u |
|---|---|
| Brzina skeniranja | `rayon` paralelni obilazak po direktorijumima; SSD dobro podnosi paralelne upite za metapodatke |
| "Prava" velicina | alocirani blokovi (`st_blocks * 512`), ne logicka duzina, pa sparse i kompresovani fajlovi nisu precenjeni |
| Hardlinkovi | broje se jednom: `(dev, ino)` set za fajlove sa `nlink > 1` |
| Mount-ovi | ne ulazi u druge volumene: poredi `st_dev` sa korenom (`--cross-fs` da se iskljuci) |
| Symlinkovi | `symlink_metadata`, nikad ne prati linkove (nema dvostrukog brojanja ni petlji) |
| Nedostupni folderi | broji greske, prijavljuje ih i nastavlja; razlika do zauzetog prostora se prikazuje kao "hidden space" |
| Hiljade sitnih fajlova | grupisu se u "smaller objects", prag po uglu (`--min-angle`) |
| Bezbedno brisanje | App: Collector (korpa) + potvrda + Trash. CLI: *dry-run* po defaultu, `--delete` + potvrda |
| Boot disk (APFS) | `/` je zapecaceni sistemski volumen, pa app skenira `/System/Volumes/Data` |
| Azuriranje posle brisanja | bez ponovnog skeniranja: `Tree::remove` oduzima velicinu od predaka |

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
