//! `bloom`: the Diskbloom command line.

mod clean_cmd;
mod render;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use diskbloom_core::{Scanner, Tree};
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(
    name = "bloom",
    version,
    about = "Diskbloom: see what takes up disk space and clean it up"
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(clap::Args)]
struct ScanOpts {
    /// Folder to scan
    #[arg(default_value = ".")]
    path: PathBuf,
    /// Also enter other mounted volumes
    #[arg(long)]
    cross_fs: bool,
}

#[derive(Subcommand)]
enum Cmd {
    /// Print the biggest folders and files as a tree
    Top {
        #[command(flatten)]
        scan: ScanOpts,
        /// Tree depth
        #[arg(short, long, default_value_t = 2)]
        depth: usize,
        /// Items per level
        #[arg(short = 'n', long, default_value_t = 10)]
        top: usize,
    },
    /// Write an interactive sunburst map to an HTML file
    Map {
        #[command(flatten)]
        scan: ScanOpts,
        /// Output HTML file
        #[arg(short, long, default_value = "diskbloom.html")]
        out: PathBuf,
        /// Items narrower than this angle (degrees) are merged into "smaller objects"
        #[arg(long, default_value_t = 0.05)]
        min_angle: f64,
        /// Maximum depth stored in the HTML
        #[arg(long, default_value_t = 14)]
        max_depth: usize,
    },
    /// Find regenerable data (builds, caches, dependencies). Dry run unless --delete.
    Clean {
        #[command(flatten)]
        scan: ScanOpts,
        #[command(flatten)]
        opts: clean_cmd::CleanOpts,
    },
}

fn main() -> Result<()> {
    match Cli::parse().cmd {
        Cmd::Top { scan, depth, top } => render::print_tree(&run_scan(&scan)?, depth, top),
        Cmd::Map {
            scan,
            out,
            min_angle,
            max_depth,
        } => {
            let html = render::html(&run_scan(&scan)?, min_angle, max_depth);
            std::fs::write(&out, html).with_context(|| format!("writing {}", out.display()))?;
            println!("map saved: {}", out.display());
        }
        Cmd::Clean { scan, opts } => {
            let categories = opts.categories()?;
            clean_cmd::run(&run_scan(&scan)?, &opts, &categories)?;
        }
    }
    Ok(())
}

/// Scans with a live counter on stderr when it is a terminal.
fn run_scan(opts: &ScanOpts) -> Result<Tree> {
    let root = std::fs::canonicalize(&opts.path)
        .with_context(|| format!("cannot open {}", opts.path.display()))?;
    if cfg!(target_os = "macos") && root == Path::new("/") && !opts.cross_fs {
        eprintln!(
            "note: on macOS your files are on /System/Volumes/Data (\"/\" is the system volume)"
        );
    }
    let scanner = Scanner::new(root.clone(), opts.cross_fs)?;
    let start = Instant::now();
    let done = AtomicBool::new(false);
    let node = std::thread::scope(|s| {
        if std::io::stderr().is_terminal() {
            s.spawn(|| {
                while !done.load(Ordering::Relaxed) {
                    eprint!("\rscanning… {} items", scanner.scanned());
                    std::thread::sleep(Duration::from_millis(150));
                }
                eprint!("\r\x1b[K");
            });
        }
        let node = scanner.scan();
        done.store(true, Ordering::Relaxed);
        node
    })?;
    let errors = scanner.errors();
    let unreadable = if errors > 0 {
        format!(", {errors} unreadable (run as root to see everything)")
    } else {
        String::new()
    };
    eprintln!(
        "scanned {} items in {:.2}s{unreadable}",
        scanner.scanned(),
        start.elapsed().as_secs_f64(),
    );
    Ok(Tree::from_node(node, root))
}
