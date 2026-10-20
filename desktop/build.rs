//! Compiles the Slint interface (`ui/`). The Cupertino style is used on every platform so the app looks the same on
//! macOS, Windows and Linux.

fn main() {
    let config = slint_build::CompilerConfiguration::new().with_style("cupertino".into());
    slint_build::compile_with_config("ui/app.slint", config).expect("the Slint interface failed to compile");
}
