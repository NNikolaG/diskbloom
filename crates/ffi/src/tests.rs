use super::*;

#[test]
fn scan_layout_clean_remove() {
    let d = tempfile::tempdir().unwrap();
    let r = d.path();
    std::fs::create_dir_all(r.join("p/target/debug")).unwrap();
    std::fs::write(r.join("p/Cargo.toml"), "x").unwrap();
    std::fs::write(r.join("p/target/debug/bin"), vec![1u8; 200_000]).unwrap();
    std::fs::write(r.join("big"), vec![1u8; 300_000]).unwrap();

    let job = ScanJob::new(r.to_string_lossy().into_owned()).unwrap();
    let tree = job.run().unwrap();
    assert!(job.scanned() >= 5);
    let root = tree.root();
    let before = tree.info(root).unwrap().size;

    let segs = tree.layout(root, 6, 0.0);
    assert!(segs.iter().any(|s| s.name == "big" && s.depth == 0));
    assert!(segs.iter().any(|s| s.name == "bin" && s.depth == 3));

    let c = tree.clean_candidates();
    assert_eq!(c.len(), 1);
    assert_eq!(c[0].category, "rust-build");
    assert_eq!(tree.find(c[0].path.clone()), Some(c[0].id));

    let freed = tree.remove(c[0].id);
    assert!(freed >= 200_000);
    assert_eq!(tree.info(root).unwrap().size, before - freed);
    assert!(tree.clean_candidates().is_empty());
}

#[test]
fn largest_dupes_rescan() {
    let d = tempfile::tempdir().unwrap();
    let r = d.path();
    let data = vec![9u8; 100_000];
    std::fs::create_dir_all(r.join("x")).unwrap();
    std::fs::write(r.join("a.bin"), &data).unwrap();
    std::fs::write(r.join("x/b.bin"), &data).unwrap();
    let tree = ScanJob::new(r.to_string_lossy().into_owned())
        .unwrap()
        .run()
        .unwrap();
    assert_eq!(tree.largest_files(10, 1).len(), 2);

    let groups = DupeJob::new(tree.clone(), 1000).run().unwrap();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].files.len(), 2);
    assert_eq!(groups[0].wasted, groups[0].size);

    // a new file in x/, then refresh only x/
    std::fs::write(r.join("x/c.bin"), vec![1u8; 300_000]).unwrap();
    let before = tree.info(tree.root()).unwrap().size;
    let x = tree
        .find(r.join("x").to_string_lossy().into_owned())
        .unwrap();
    let new_x = tree.rescan(x).unwrap();
    assert!(tree.is_attached(new_x) && !tree.is_attached(x));
    assert!(tree.info(tree.root()).unwrap().size >= before + 300_000);
    assert_eq!(tree.children(new_x).len(), 2);
}

#[test]
fn cancel_reports_cancelled() {
    let d = tempfile::tempdir().unwrap();
    let job = ScanJob::new(d.path().to_string_lossy().into_owned()).unwrap();
    job.cancel();
    assert!(matches!(job.run(), Err(BloomError::Cancelled)));
}
