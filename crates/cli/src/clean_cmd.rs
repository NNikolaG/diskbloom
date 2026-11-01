//! `bloom clean`.

use anyhow::{Result, bail};
use diskbloom_core::clean::{self, Candidate, Category};
use diskbloom_core::{Tree, human};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::Path;

/// Candidates listed in the report.
const SHOWN: usize = 25;

#[derive(clap::Args)]
pub struct CleanOpts {
    /// Really delete (asks for confirmation)
    #[arg(long)]
    delete: bool,
    /// Do not ask for confirmation (only with --delete)
    #[arg(short, long)]
    yes: bool,
    /// Only these categories, e.g. rust-build,node-deps
    #[arg(short, long, value_delimiter = ',')]
    category: Vec<String>,
    /// Minimum candidate size in MB
    #[arg(long, default_value_t = 0.0)]
    min_mb: f64,
    /// Also include categories that need review (emulators, VMs, backups, installers)
    #[arg(long)]
    include_review: bool,
}

impl CleanOpts {
    /// The `--category` values, checked.
    pub fn categories(&self) -> Result<Vec<Category>> {
        self.category
            .iter()
            .map(|id| {
                let Some(c) = Category::from_id(id) else {
                    let known: Vec<_> = Category::ALL.iter().map(|c| c.id()).collect();
                    bail!("unknown category '{id}'; known: {}", known.join(", "))
                };
                Ok(c)
            })
            .collect()
    }

    /// Whether a candidate passes the filters. A category asked for by name is shown
    /// even if it needs review.
    fn wants(&self, c: &Candidate, categories: &[Category]) -> bool {
        let min = (self.min_mb.max(0.0) * 1_000_000.0) as u64;
        c.size >= min
            && (categories.is_empty() || categories.contains(&c.category))
            && (c.is_safe() || self.include_review || !categories.is_empty())
    }
}

pub fn run(tree: &Tree, opts: &CleanOpts, categories: &[Category]) -> Result<()> {
    let candidates: Vec<_> = clean::find(tree)
        .into_iter()
        .filter(|c| opts.wants(c, categories))
        .collect();
    if candidates.is_empty() {
        println!("nothing to clean up.");
        return Ok(());
    }
    report(&candidates, tree.root_path());
    if !opts.delete {
        println!("\n(dry run) add --delete to remove these.");
        return Ok(());
    }
    let total: u64 = candidates.iter().map(|c| c.size).sum();
    let question = format!(
        "Delete {} items ({})? Type 'yes': ",
        candidates.len(),
        human(total)
    );
    if !opts.yes && !confirm(&question)? {
        println!("cancelled.");
        return Ok(());
    }
    let mut freed = 0;
    for c in &candidates {
        match clean::delete(c) {
            Ok(()) => freed += c.size,
            Err(e) => eprintln!("could not delete {}: {e}", c.path.display()),
        }
    }
    println!("freed {}", human(freed));
    Ok(())
}

fn report(candidates: &[Candidate], root: &Path) {
    let mut by_category: BTreeMap<Category, (u64, usize)> = BTreeMap::new();
    for c in candidates {
        let (size, count) = by_category.entry(c.category).or_default();
        *size += c.size;
        *count += 1;
    }
    let mut rows: Vec<_> = by_category.into_iter().collect();
    rows.sort_by_key(|(_, (size, _))| std::cmp::Reverse(*size));
    println!("By category:");
    for (category, (size, count)) in &rows {
        println!(
            "  {:<20} {:>10}  ({count} items)",
            category.id(),
            human(*size)
        );
    }
    println!("\nLargest candidates:");
    for c in candidates.iter().take(SHOWN) {
        let rel = c.path.strip_prefix(root).unwrap_or(&c.path);
        println!(
            "  {:>10}  [{}{}]  {}{}",
            human(c.size),
            c.category,
            if c.is_safe() { "" } else { ", review" },
            rel.display(),
            if c.is_dir { "/" } else { "" }
        );
    }
    if candidates.len() > SHOWN {
        println!("  … and {} more", candidates.len() - SHOWN);
    }
    let total: u64 = candidates.iter().map(|c| c.size).sum();
    println!("\nTotal: {}", human(total));
}

fn confirm(question: &str) -> std::io::Result<bool> {
    print!("{question}");
    std::io::stdout().flush()?;
    let mut answer = String::new();
    std::io::stdin().read_line(&mut answer)?;
    Ok(answer.trim() == "yes")
}
