(function () {
  "use strict";

  var path = (window.location.pathname || "").toLowerCase();
  var isReset = path.indexOf("/reset") === 0 || path.indexOf("/account/reset") === 0;
  var action = isReset ? "reset" : "verify";
  var appName = "Adfoot";

  var copy = {
    reset: {
      initialTitle: "Créer votre mot de passe",
      initialDescription:
        "Saisissez un mot de passe pour activer votre compte.",
      processing: "Vérification du lien...",
      successTitle: "Mot de passe créé",
      successDescription:
        "Vous pouvez maintenant vous connecter à Adfoot.",
      invalidLink:
        "Ce lien est invalide ou expiré. Demandez un nouveau lien à l'administration.",
    },
    verify: {
      initialTitle: "Vérification e-mail",
      initialDescription:
        "Validation de votre adresse e-mail en cours.",
      processing: "Vérification du lien...",
      successTitle: "E-mail vérifié",
      successDescription:
        "Ouvrez le lien de création du mot de passe.",
      invalidLink:
        "Ce lien est invalide ou expiré. Demandez un nouveau lien à l'administration.",
    },
  }[action];

  var titleNode = document.getElementById("action-title");
  var descriptionNode = document.getElementById("action-description");
  var hintNode = document.getElementById("action-hint");
  var metaNode = document.getElementById("action-meta");
  var statusNode = document.getElementById("action-status");
  var successPanelNode = document.getElementById("success-panel");
  var resetForm = document.getElementById("reset-form");
  var passwordNode = document.getElementById("new-password");
  var confirmNode = document.getElementById("confirm-password");
  var submitNode = document.getElementById("submit-password");

  function setText(node, text) {
    if (node) node.textContent = text;
  }

  function setState(kind, title, description, status) {
    setText(titleNode, title);
    setText(descriptionNode, description);
    setText(statusNode, status || "");
    if (statusNode) {
      statusNode.className = "status " + (kind || "info");
      statusNode.hidden = !status;
    }
    if (successPanelNode && kind !== "success") {
      successPanelNode.hidden = true;
    }
  }

  function setBusy(isBusy) {
    if (submitNode) {
      submitNode.disabled = isBusy;
      submitNode.textContent = isBusy ?
        "Traitement en cours..." :
        "Définir le mot de passe";
    }
  }

  function parseParamsFromUrl(rawUrl, depth) {
    var out = {};
    if (!rawUrl || depth > 3) return out;

    try {
      var parsed = new URL(rawUrl, window.location.origin);
      parsed.searchParams.forEach(function (value, key) {
        if (!out[key]) out[key] = value;
      });

      if (parsed.hash && parsed.hash.length > 1) {
        new URLSearchParams(parsed.hash.slice(1)).forEach(function (value, key) {
          if (!out[key]) out[key] = value;
        });
      }

      ["link", "continueUrl", "deep_link_id"].forEach(function (key) {
        if (out[key]) {
          var nested = parseParamsFromUrl(out[key], depth + 1);
          Object.keys(nested).forEach(function (nestedKey) {
            if (!out[nestedKey]) out[nestedKey] = nested[nestedKey];
          });
        }
      });
    } catch (_) {}

    return out;
  }

  function firebaseRequest(methodName, payload, apiKey) {
    return fetch(
      "https://identitytoolkit.googleapis.com/v1/" +
        methodName +
        "?key=" +
        encodeURIComponent(apiKey),
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(payload),
      }
    ).then(function (response) {
      return response.json().then(function (body) {
        if (!response.ok || body.error) {
          var code =
            body && body.error && body.error.message ?
              body.error.message :
              "REQUEST_FAILED";
          var error = new Error(code);
          error.code = code;
          throw error;
        }
        return body;
      });
    });
  }

  function userMessage(error) {
    var code = (error && error.code ? error.code : "").toString();
    if (code.indexOf("EXPIRED_OOB_CODE") >= 0) {
      return "Ce lien a expiré. Demandez un nouveau lien à l'administration.";
    }
    if (code.indexOf("INVALID_OOB_CODE") >= 0) {
      return "Ce lien est invalide ou a déjà été utilisé.";
    }
    if (code.indexOf("WEAK_PASSWORD") >= 0) {
      return "Le mot de passe est trop faible. Utilisez au moins 6 caractères.";
    }
    if (code.indexOf("API_KEY_INVALID") >= 0) {
      return "La configuration Firebase de cette page est invalide.";
    }
    return "L'opération a échoué. Vérifiez le lien puis réessayez.";
  }

  function revealSuccess(title, description) {
    setState("success", title, description, "Opération terminée avec succès.");
    if (resetForm) resetForm.hidden = true;
    if (successPanelNode) successPanelNode.hidden = false;
    if (hintNode) hintNode.hidden = false;
  }

  function configureLinks() {
    if (hintNode) hintNode.hidden = true;
    if (metaNode) {
      metaNode.textContent =
        "Environnement : " +
        window.location.host +
        " | Action: " +
        (isReset ? "resetPassword" : "verifyEmail");
    }
  }

  function initReset(params) {
    var apiKey = params.apiKey;
    var oobCode = params.oobCode;
    if (!apiKey || !oobCode) {
      setState("danger", copy.initialTitle, copy.invalidLink, copy.invalidLink);
      return;
    }

    setState("info", copy.initialTitle, copy.initialDescription, copy.processing);
    firebaseRequest("accounts:resetPassword", {oobCode: oobCode}, apiKey)
      .then(function (result) {
        var email = result.email || "";
        setState(
          "info",
          copy.initialTitle,
          email ?
            "Compte : " + email + ". Saisissez votre nouveau mot de passe." :
            copy.initialDescription,
          ""
        );
        if (resetForm) resetForm.hidden = false;
      })
      .catch(function (error) {
        setState("danger", copy.initialTitle, userMessage(error), userMessage(error));
      });

    if (resetForm) {
      resetForm.addEventListener("submit", function (event) {
        event.preventDefault();
        var password = passwordNode ? passwordNode.value : "";
        var confirmation = confirmNode ? confirmNode.value : "";

        if (password.length < 6) {
          setState(
            "danger",
            copy.initialTitle,
            copy.initialDescription,
            "Le mot de passe doit contenir au moins 6 caractères."
          );
          return;
        }
        if (password !== confirmation) {
          setState(
            "danger",
            copy.initialTitle,
            copy.initialDescription,
            "Les deux mots de passe ne correspondent pas."
          );
          return;
        }

        setBusy(true);
        setState("info", copy.initialTitle, copy.initialDescription, "Création du mot de passe...");
        firebaseRequest(
          "accounts:resetPassword",
          {oobCode: oobCode, newPassword: password},
          apiKey
        )
          .then(function () {
            revealSuccess(copy.successTitle, copy.successDescription);
          })
          .catch(function (error) {
            setState("danger", copy.initialTitle, copy.initialDescription, userMessage(error));
          })
          .finally(function () {
            setBusy(false);
          });
      });
    }
  }

  function initVerify(params) {
    var apiKey = params.apiKey;
    var oobCode = params.oobCode;
    if (!apiKey || !oobCode) {
      setState("danger", copy.initialTitle, copy.invalidLink, copy.invalidLink);
      return;
    }

    setState("info", copy.initialTitle, copy.initialDescription, copy.processing);
    firebaseRequest("accounts:update", {oobCode: oobCode}, apiKey)
      .then(function () {
        revealSuccess(copy.successTitle, copy.successDescription);
      })
      .catch(function (error) {
        setState("danger", copy.initialTitle, userMessage(error), userMessage(error));
      });
  }

  configureLinks();
  var params = parseParamsFromUrl(window.location.href, 0);
  if (isReset) {
    initReset(params);
  } else {
    initVerify(params);
  }
})();
