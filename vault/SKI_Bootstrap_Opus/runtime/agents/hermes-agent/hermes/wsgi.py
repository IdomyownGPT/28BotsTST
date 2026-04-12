# ═══════════════════════════════════════════════════════════════
# Hermes WSGI entrypoint — wird von waitress-serve geladen.
#
#   waitress-serve --listen=*:9377 --threads=8 hermes.wsgi:app
#
# Importiert die Flask-App aus __main__ und triggert Startup-Init.
# ═══════════════════════════════════════════════════════════════

from hermes.__main__ import app, startup_init

# Einmalige Initialisierung beim Import (Model-Bind, Vault-Check)
startup_init()
