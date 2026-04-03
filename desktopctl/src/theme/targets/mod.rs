use crate::theme::schema::{ColorScheme, ThemeState};
use std::{collections::BTreeMap, io};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Assembly {
    Import,
    Standalone,
    Command,
    Concat,
}

pub type CommandBatch = Vec<Vec<String>>;
pub type GenerateFn = fn(&ColorScheme, &ThemeState) -> crate::Result<GeneratedContent>;
pub type HookFn = fn(&ColorScheme, &ThemeState) -> crate::Result<()>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GeneratedContent {
    Text(String),
    Commands(CommandBatch),
}

impl GeneratedContent {
    pub fn text(content: impl Into<String>) -> Self {
        Self::Text(content.into())
    }

    pub fn commands(commands: CommandBatch) -> Self {
        Self::Commands(commands)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TargetMetadata {
    pub name: &'static str,
    pub assembly: Assembly,
    pub output_path: Option<&'static str>,
    pub base_path: Option<&'static str>,
    pub extra_outputs: &'static [&'static str],
    pub reload_cmd: Option<&'static [&'static str]>,
    pub comment: Option<&'static str>,
    pub sync_safe: bool,
}

impl TargetMetadata {
    pub const fn new(name: &'static str, assembly: Assembly) -> Self {
        Self {
            name,
            assembly,
            output_path: None,
            base_path: None,
            extra_outputs: &[],
            reload_cmd: None,
            comment: None,
            sync_safe: true,
        }
    }
}

pub trait Target: Send + Sync {
    fn metadata(&self) -> &TargetMetadata;
    fn generate(&self, colors: &ColorScheme, state: &ThemeState)
    -> crate::Result<GeneratedContent>;

    fn persist(&self, _colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
        Ok(())
    }

    fn on_apply(&self, _colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
        Ok(())
    }
}

pub struct FunctionTarget {
    metadata: TargetMetadata,
    generate: GenerateFn,
    persist: Option<HookFn>,
    on_apply: Option<HookFn>,
}

impl FunctionTarget {
    pub const fn new(metadata: TargetMetadata, generate: GenerateFn) -> Self {
        Self {
            metadata,
            generate,
            persist: None,
            on_apply: None,
        }
    }

    pub const fn with_hooks(
        metadata: TargetMetadata,
        generate: GenerateFn,
        persist: Option<HookFn>,
        on_apply: Option<HookFn>,
    ) -> Self {
        Self {
            metadata,
            generate,
            persist,
            on_apply,
        }
    }
}

impl Target for FunctionTarget {
    fn metadata(&self) -> &TargetMetadata {
        &self.metadata
    }

    fn generate(
        &self,
        colors: &ColorScheme,
        state: &ThemeState,
    ) -> crate::Result<GeneratedContent> {
        (self.generate)(colors, state)
    }

    fn persist(&self, colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
        if let Some(hook) = self.persist {
            hook(colors, state)?;
        }
        Ok(())
    }

    fn on_apply(&self, colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
        if let Some(hook) = self.on_apply {
            hook(colors, state)?;
        }
        Ok(())
    }
}

#[derive(Default)]
pub struct TargetRegistry {
    targets: BTreeMap<&'static str, Box<dyn Target>>,
}

impl TargetRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register<T>(&mut self, target: T) -> crate::Result<()>
    where
        T: Target + 'static,
    {
        self.register_boxed(Box::new(target))
    }

    pub fn register_boxed(&mut self, target: Box<dyn Target>) -> crate::Result<()> {
        validate_metadata(target.metadata())?;
        let name = target.metadata().name;
        if self.targets.contains_key(name) {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                format!("Duplicate TARGET_NAME '{name}'"),
            )
            .into());
        }
        self.targets.insert(name, target);
        Ok(())
    }

    pub fn register_function(
        &mut self,
        metadata: TargetMetadata,
        generate: GenerateFn,
    ) -> crate::Result<()> {
        self.register(FunctionTarget::new(metadata, generate))
    }

    pub fn register_function_with_hooks(
        &mut self,
        metadata: TargetMetadata,
        generate: GenerateFn,
        persist: Option<HookFn>,
        on_apply: Option<HookFn>,
    ) -> crate::Result<()> {
        self.register(FunctionTarget::with_hooks(
            metadata, generate, persist, on_apply,
        ))
    }

    pub fn get(&self, name: &str) -> Option<&dyn Target> {
        self.targets.get(name).map(|target| target.as_ref())
    }

    pub fn iter(&self) -> impl Iterator<Item = (&'static str, &dyn Target)> {
        self.targets
            .iter()
            .map(|(name, target)| (*name, target.as_ref()))
    }

    pub fn names(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.targets.keys().copied()
    }
}

fn validate_metadata(metadata: &TargetMetadata) -> crate::Result<()> {
    match metadata.assembly {
        Assembly::Command => {}
        Assembly::Import | Assembly::Standalone => {
            if metadata.output_path.is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Target '{}' is missing OUTPUT_PATH", metadata.name),
                )
                .into());
            }
        }
        Assembly::Concat => {
            if metadata.output_path.is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Target '{}' is missing OUTPUT_PATH", metadata.name),
                )
                .into());
            }
            if metadata.base_path.is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Target '{}' is missing BASE_PATH", metadata.name),
                )
                .into());
            }
        }
    }
    Ok(())
}

pub fn build_registry() -> crate::Result<TargetRegistry> {
    let registry = TargetRegistry::new();
    Ok(registry)
}
