// Pure state derivation helpers.
// Keep UI logic deterministic: compute everything from (a) rpm-ostree facts and (b) last check result.

import { extractBuildTime, formatTimestamp, extractOrigin, extractTag, extractDigest, inferVariantAndChannelFromOrigin } from './rpm_ostree.js';

function _bestOriginWithTag(booted) {
  const candidates = [
    booted?.origin,
    booted?.['container-image-reference'],
    booted?.container_image_reference,
    extractOrigin(booted)
  ].filter(Boolean);

  const withTag = candidates.find(r => Boolean(extractTag(r)));
  return withTag || candidates[0] || '';
}

export function buildFacts({ i18n, osRelease, parsed }) {
  const distroName = osRelease?.NAME || 'Borshevik';

  const booted = parsed?.booted || null;
  const staged = parsed?.staged || null;
  const pending = parsed?.pending || null;
  const rollback = parsed?.rollback || null;

  const buildTs = extractBuildTime(booted);
  const buildTime = buildTs ? formatTimestamp(buildTs) : i18n.t('unknown');

  const currentOrigin = _bestOriginWithTag(booted);
  const tag = extractTag(currentOrigin);
  const channel = tag || i18n.t('unknown');

  const digest = extractDigest(booted) || i18n.t('unknown');
  
  const variantInfo = inferVariantAndChannelFromOrigin(currentOrigin);
  let variantName = 'custom';
  if (variantInfo.variant === 'standard') {
    variantName = 'borshevik';
  } else if (variantInfo.variant === 'nvidia') {
    variantName = 'borshevik-nvidia';
  }

  const nextDeployment = staged || pending;
  const nextTs = extractBuildTime(nextDeployment);
  const nextTime = nextDeployment ? (nextTs ? formatTimestamp(nextTs) : i18n.t('unknown')) : '';

  const hasRollback = Boolean(rollback && rollback !== booted);
  const rbTs = extractBuildTime(rollback);
  const rollbackTime = hasRollback ? (rbTs ? formatTimestamp(rbTs) : i18n.t('unknown')) : i18n.t('not_available');

  return {
    distroName,
    buildTime,
    channel,
    digest,
    variant: variantName,
    currentOrigin,
    needsReboot: Boolean(nextDeployment),
    nextTime,
    hasRollback,
    rollbackTime
  };
}

export function computeUiState({ i18n, facts, check }) {
  // Primary action is always Check/Update.
  // If a deployment is staged/pending, primary action reverts to Check.
  const showCheckSpinner = check?.phase === 'checking';

  let primaryMode = 'check';
  if (check?.phase === 'available')
    primaryMode = 'update';

  // Status message line under the primary area.
  let statusText = '';
  if (check?.phase === 'available') {
    const size = check?.downloadSize || i18n.t('unknown');
    statusText = `${i18n.t('updates_available')} ${i18n.t('download_size')}: ${size}.`;
  } else if (facts.needsReboot) {
    statusText = i18n.t('update_pending_reboot');
  } else if (check?.phase === 'no_updates') {
    statusText = i18n.t('no_new_updates');
  } else if (check?.phase === 'error') {
    statusText = check?.message ? `${i18n.t('error')}: ${check.message}` : i18n.t('error');
  } else {
    statusText = check?.message || '';
  }

  return {
    showCheckSpinner,
    primaryMode,
    primaryLabel: primaryMode === 'update' ? i18n.t('primary_update') : i18n.t('primary_check'),
    statusText
  };
}
