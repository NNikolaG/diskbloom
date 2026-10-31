mod render;

use clap::{Parser, Subcommand};
use diskbloom_core::{Scanner, Tree, clean, human};
use std::collections::BTreeMap;
use std::io::{IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(name = "bloom", version, about = "diskbloom: analiza i ciscenje diska")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(clap::Args)]
struct ScanOpts {
    /// Folder koji se skenira
    #[arg(default_value = ".")]
    path: PathBuf,
    /// Ulazi i u druge mount-ovane volumene
    #[arg(long)]
    cross_fs: bool,
}

#[derive(Subcommand)]
enum Cmd {
    /// Tekstualni pregled najvecih foldera/fajlova
    Top {
        #[command(flatten)]
        scan: ScanOpts,
        /// Dubina stabla
        #[arg(short, long, default_value_t = 2)]
        depth: usize,
        /// Koliko stavki po nivou
        #[arg(short = 'n', long, default_value_t = 10)]
        top: usize,
    },
    /// Interaktivna sunburst mapa u HTML fajlu
    Map {
        #[command(flatten)]
        scan: ScanOpts,
        /// Izlazni HTML fajl
        #[arg(short, long, default_value = "diskbloom.html")]
        out: PathBuf,
        /// Objekti manji od ovog ugla (stepeni) idu u "smaller objects"
        #[arg(long, default_value_t = 0.05)]
        min_angle: f64,
        /// Maksimalna dubina u HTML-u
        #[arg(long, default_value_t = 14)]
        max_depth: usize,
    },
    /// Pronalazi regenerisivo smece (build, kes, deps). Dry-run po defaultu.
    Clean {
        #[command(flatten)]
        scan: ScanOpts,
        /// Zaista obrisi (uz potvrdu)
        #[arg(long)]
        delete: bool,
        /// Bez pitanja za potvrdu (samo uz --delete)
        #[arg(short, long)]
        yes: bool,
        /// Samo ove kategorije (npr. rust-build,node-deps)
        #[arg(short, long, value_delimiter = ',')]
        category: Vec<String>,
        /// Minimalna velicina kandidata u MB
        #[arg(long, default_value_t = 0.0)]
        min_mb: f64,
    },
}

fn run_scan(opts: &ScanOpts) -> std::io::Result<Tree> {
    let root = std::fs::canonicalize(&opts.path)?;
    if cfg!(target_os = "macos") && root == Path::new("/") && !opts.cross_fs {
        eprintln!(
            "napomena: na macOS-u su korisnicki podaci na /System/Volumes/Data (\"/\" je sistemski volumen)"
        );
    }
    let scanner = Scanner::new(&root, opts.cross_fs)?;
    let start = Instant::now();
    let done = AtomicBool::new(false);
    let node = std::thread::scope(|s| {
        if std::io::stderr().is_terminal() {
            s.spawn(|| {
                while !done.load(Ordering::Relaxed) {
                    eprint!(
                        "\rskeniram… {} objekata",
                        scanner.scanned.load(Ordering::Relaxed)
                    );
                    std::thread::sleep(Duration::from_millis(150));
                }
                eprint!("\r\x1b[K");
            });
        }
        let r = scanner.scan(&root);
        done.store(true, Ordering::Relaxed);
        r
    })?;
    let errs = scanner.errors.load(Ordering::Relaxed);
    eprintln!(
        "skenirano {} objekata za {:.2}s{}",
        scanner.scanned.load(Ordering::Relaxed),
        start.elapsed().as_secs_f64(),
        if errs > 0 {
            format!(", {errs} nedostupno (pokreni kao root za potpun pregled)")
        } else {
            String::new()
        }
    );
    Ok(Tree::from_node(node, root))
}

fn main() {
    if let Err(e) = real_main() {
        eprintln!("greska: {e}");
        std::process::exit(1);
    }
}

fn real_main() -> std::io::Result<()> {
    match Cli::parse().cmd {
        Cmd::Top { scan, depth, top } => {
            render::print_tree(&run_scan(&scan)?, depth, top);
        }
        Cmd::Map {
            scan,
            out,
            min_angle,
            max_depth,
        } => {
            std::fs::write(&out, render::html(&run_scan(&scan)?, min_angle, max_depth))?;
            println!("mapa sacuvana: {}", out.display());
        }
        Cmd::Clean {
            scan,
            delete,
            yes,
            category,
            min_mb,
        } => {
            let tree = run_scan(&scan)?;
            let root = tree.root_path();
            let min = (min_mb * 1_000_000.0) as u64;
            let cands: Vec<_> = clean::find(&tree)
                .into_iter()
                .filter(|c| {
                    c.size >= min
                        && (category.is_empty() || category.iter().any(|k| k == c.category))
                })
                .collect();
            if cands.is_empty() {
                println!("nema sta da se cisti.");
                return Ok(());
            }
            report(&cands, root);
            if !delete {
                println!("\n(dry-run) dodaj --delete da obrises.");
                return Ok(());
            }
            let total: u64 = cands.iter().map(|c| c.size).sum();
            if !yes
                && !confirm(&format!(
                    "Obrisati {} stavki ({})? upisi 'yes': ",
                    cands.len(),
                    human(total)
                ))?
            {
                println!("otkazano.");
                return Ok(());
            }
            let mut freed = 0;
            for c in &cands {
                match clean::delete(c) {
                    Ok(()) => freed += c.size,
                    Err(e) => eprintln!("ne mogu da obrisem {}: {e}", c.path.display()),
                }
            }
            println!("oslobodjeno {}", human(freed));
        }
    }
    Ok(())
}

fn report(cands: &[clean::Candidate], root: &Path) {
    let mut by_cat: BTreeMap<&str, (u64, usize)> = BTreeMap::new();
    for c in cands {
        let e = by_cat.entry(c.category).or_default();
        e.0 += c.size;
        e.1 += 1;
    }
    println!("Po kategorijama:");
    let mut cats: Vec<_> = by_cat.into_iter().collect();
    cats.sort_by_key(|c| std::cmp::Reverse(c.1.0));
    for (cat, (size, n)) in &cats {
        println!("  {:<14} {:>10}  ({n} stavki)", cat, human(*size));
    }
    println!("\nNajveci kandidati:");
    for c in cands.iter().take(25) {
        let rel = c.path.strip_prefix(root).unwrap_or(&c.path);
        println!(
            "  {:>10}  [{}]  {}{}",
            human(c.size),
            c.category,
            rel.display(),
            if c.is_dir { "/" } else { "" }
        );
    }
    if cands.len() > 25 {
        println!("  … i jos {}", cands.len() - 25);
    }
    let total: u64 = cands.iter().map(|c| c.size).sum();
    println!("\nUkupno za ciscenje: {}", human(total));
}

fn confirm(q: &str) -> std::io::Result<bool> {
    print!("{q}");
    std::io::stdout().flush()?;
    let mut s = String::new();
    std::io::stdin().read_line(&mut s)?;
    Ok(s.trim() == "yes")
}
