/* eslint-disable linebreak-style */

import type {SupportedRegion} from "firebase-functions/v2/options";

const REGION: SupportedRegion = "europe-west1";

// Keep lightweight Gen 2 functions on the lower Gen 1 CPU profile to reduce
// Cloud Run regional CPU quota pressure without changing the callable API.
const LOW_CPU_REGION_OPTIONS = {
  region: REGION,
  cpu: "gcf_gen1" as const,
};

export {REGION, LOW_CPU_REGION_OPTIONS};
