# Interrupted artwork refresh — recovery checkpoint

The full artwork refresh is NOT complete. No APK was built or uploaded for this refresh, and neither main nor release was moved.

The verified missing-portrait repair remains in the parent history at `8718198cf20e7ad9902fb82d0be518ebea8a2efa`: W005/S3 m_mid_researcher, W006/S3 m_mid_worker, W006/S4 f_mid_waitress, registry entries and regression tests. Its CI run was https://github.com/amin-salem/The-Case/actions/runs/42227416926 .

The execution workspace was replaced during the larger refresh. Most new local artwork and uncommitted client changes were not recovered. Do not treat the earlier generation counters or planned 70-scene/371-suspect catalog as shipped coverage. The application still uses the parent's artwork mapping, so repeated artwork remains.

Two verified, compressed artwork blobs are preserved here for subsequent integration:

- `recovered-art/m_old_w005_s1.webp`: proposed W005/S1 portrait.
- `recovered-art/m_mid_c013_s3.webp`: proposed C013/S3 portrait.

These are source/recovery assets only; they are not registered or used by the application yet. Remaining recovered PNGs were saved separately for the owner, with incomplete identity metadata; do not assign them to cases by guessing.

To resume: read current main and release, preserve concurrent edits, restore or regenerate missing art in small durably committed batches, reconstruct case/suspect-specific lookup and the corresponding album/location mapping, and verify offline cached cases. Export portraits at 512px WebP and scene images within 768x512, visually compare compression, audit actual references and all case coverage, then run the full Flutter/server CI at the exact new head. Only after that should a new version be built and uploaded to Bazaar.

The previous build 82 workflow's upload step logged an HTTP 000 failure despite the overall workflow succeeding. Verify the actual upload/commit log on the next release; workflow green alone is not proof of Bazaar delivery. The existing uploader creates an unpublished submission, not automatic public publication.
