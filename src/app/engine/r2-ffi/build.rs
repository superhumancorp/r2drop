// r2-ffi/build.rs — Generates r2_ffi.h C header via cbindgen
// The header is placed at the crate root so Xcode can reference it.
// If cbindgen fails (e.g. unsupported syntax), the existing header is kept.
fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let config = cbindgen::Config::from_file("cbindgen.toml").unwrap_or_default();
    match cbindgen::Builder::new()
        .with_crate(&crate_dir)
        .with_config(config)
        .generate()
    {
        Ok(bindings) => {
            bindings.write_to_file("r2_ffi.h");
        }
        Err(e) => {
            eprintln!("cargo:warning=cbindgen failed: {e}. Using existing r2_ffi.h");
        }
    }
}