# Weblate shared glossary

Flux News uses one project-wide Weblate glossary for terminology shared by the
Android, iOS and macOS components.

The glossary is stored as bilingual TermBase eXchange (TBX) files under
`Weblate/Glossary/`. English is the source language. There is intentionally no
`en.tbx`: Weblate uses the component source language for source terms and maps
the target language from the file name.

## Initial terminology

The initial glossary contains a deliberately small set of product and UI terms.

- `Flux News`, `FluxNews` and `Miniflux` are terminology entries marked as
  not translatable.
- Cross-platform product terms such as `Listening List`, `Feed`,
  `Category`, `Sync`, `Background Sync`, `Unread`, `Mark as Read`,
  `Reader`, `Starred`, `Download`, `Downloads`, `Now Playing`,
  `Search` and `Settings` are marked as terminology.
- Target-language values are prefilled only when the existing native iOS String
  Catalog currently marks that value as `translated`. Existing
  `needs_review` values are deliberately not promoted into preferred glossary
  terminology.

Missing target terms should be translated and reviewed in Weblate.

## Weblate component

Create one component named **Glossary** with:

- **Repository:** `weblate://flux-news/android`
- **Version control:** GitHub Pull Request
- **File format:** TermBase eXchange (TBX)
- **File mask:** `Weblate/Glossary/*.tbx`
- **Source language:** English
- **Monolingual base language file:** empty
- **Template for new translations:** empty
- **Use as glossary:** enabled
- **Manage strings:** enabled
- **Restricted component:** disabled
- **Create pull requests:** enabled
- **Automatic pull-request merge:** disabled

Unlike the application localization components, source-string management is
enabled for the glossary because glossary terms are intentionally maintained in
Weblate.

For adding new glossary languages, keep the project behavior that creates a new
language file. Weblate synchronizes glossary languages with the regular
components in the project, so a newly introduced application language can gain
its corresponding glossary file.

## Maintenance rules

Keep the glossary small and terminology-focused. Do not turn it into a general
dictionary. Add terms when consistency across platforms or translators matters.

Use **Terminology** for preferred cross-language terms, **Untranslatable** for
product/project names that must stay unchanged, and **Forbidden translation**
only when a specific misleading target wording must be prevented.

When a previously unreviewed app translation is accepted in Weblate, the
glossary can be filled independently with the preferred term. The glossary is
guidance for translators; it does not replace the Android resources or Apple
String Catalogs.
