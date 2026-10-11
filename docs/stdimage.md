# Image fields — django-stdimage

`User.picture` uses `StdImageField` from a **maintained fork**
(`django-stdimage @ git+https://github.com/igorkhaylov/django-stdimage.git`). The fork
ships sensible **default variations**, so a plain field already exposes resized renditions
(e.g. `obj.picture.small`) without extra configuration.

```python
from stdimage.models import StdImageField

class User(...):
    picture = StdImageField(_("Photo"), upload_to="users/%Y/%m/%d/", blank=True, null=True)
```

In the admin, the preview uses a default variation:

```python
return format_html('<img src="{}" height="200" />', obj.picture.small.url)
```

## Project-wide default variations

Since fork `v1.2.0`, the default set used by every field declared without `variations`
can be changed in one place instead of per field:

```python
# backend/config/settings/third_party.py
STDIMAGE_DEFAULT_VARIATIONS = {
    "thumbnail": {"width": 150, "height": 150, "crop": True},
    "card": {"width": 600, "height": None},
}
```

Resolution order: explicit `variations=` on the field, then this setting (when defined;
`{}` means no default variations), then the fork's built-in defaults. The resolved set is
written into migrations like explicit variations, so changing the setting is an
`AlterField` (`make dev makemigrations && make dev migrate`) plus `rendervariations` for
existing files. The template does not define the setting: the built-in defaults apply.

## Declaring custom variations

To control sizes explicitly, pass `variations`. Each entry becomes an attribute on the
field file (`obj.picture.<name>.url`):

```python
picture = StdImageField(
    _("Photo"),
    upload_to="users/%Y/%m/%d/",
    variations={
        "large": {"width": 800, "height": 800},
        "thumbnail": {"width": 100, "height": 100, "crop": True},
    },
    blank=True,
    null=True,
)
```

- `width` / `height` — bounding box; the image is scaled to fit.
- `crop: True` — crop to exactly `width × height` (otherwise aspect ratio is preserved).
- Access in templates/serializers: `instance.picture.large.url`, `instance.picture.thumbnail.url`.
- The original is always available as `instance.picture.url`.

> When you change `variations`, run `make dev makemigrations && make dev migrate` —
> the variation set is stored on the field and affects migrations.

## Regenerating renditions

If you add a variation to a field that already has stored images, re-render them with the
management command provided by stdimage:

```bash
make dev bash
python manage.py rendervariations 'users.User.picture'
```

## Deleting files on model delete

`django-cleanup` is installed, so when a model instance (or its image field) is deleted or
replaced, the underlying file in S3/MinIO is removed automatically — no manual cleanup
needed.

## Maintaining the fork

The fork is maintained by the project owner. To bump it:

1. Tag a release in the fork repo (e.g. `v1.2.0`).
2. Update the ref in `backend/pyproject.toml`:
   `django-stdimage @ git+https://github.com/igorkhaylov/django-stdimage.git@v1.2.0`
3. `cd backend && uv lock --upgrade-package django-stdimage`
