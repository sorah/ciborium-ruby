#[magnus::init]
fn init(ruby: &magnus::Ruby) -> Result<(), magnus::Error> {
    use magnus::Module as _;
    ruby.define_module("Ciborium")?.define_module("Native")?;
    Ok(())
}
