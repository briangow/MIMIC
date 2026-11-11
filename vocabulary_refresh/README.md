# README #

### Refresh OMOP vocabularies with the workflow runner ###

This folder now supports the repository workflow runner instead of the older
`vocabulary_refresh.py -s10/-s20/-s30` flow.

### Current workflow ###

1. Create each BigQuery dataset that will participate in the workflow before running any DDL or upload step.
  * Create the unified view dataset named by `@voc_project.@voc_dataset`.
  * Create the Athena raw upload dataset if `@athena_dataset` will be used.
  * Create each configured custom delta raw upload dataset such as `@custom_delta_dataset_1`, `@custom_delta_dataset_2`, etc.
  * The uploader does not create datasets automatically; it only loads tables into datasets that already exist.
2. Create empty vocabulary tables in each upload dataset by running `conf/workflow_vocab_upload_ddl.conf`.
  The vocabulary table definitions come from `etl/ddl/ddl_voc_5_4_2.sql`.
3. Configure the vocabulary source directories and per-source upload datasets in `vocabulary_refresh.conf`.
4. Run `conf/workflow_vocabulary_refresh.conf` from the repository root to upload Athena and custom delta files and then rebuild the unified `voc_*` materialized views.

### Configuration ###

`vocabulary_refresh.conf` controls which local folders are loaded.

* `view_project` and `view_dataset`
  * target BigQuery project and dataset for the unified `voc_*` materialized views
  * these normally match `@voc_project` and `@voc_dataset` from `conf/<env>.etlconf`
* `athena_vocab_dir`
  * local directory containing the Athena vocabulary extract
  * leave empty to skip Athena loading
* `athena_project` and `athena_dataset`
  * upload target for the Athena raw vocabulary tables
* `custom_delta_vocab_dir_1` ... `custom_delta_vocab_dir_4`
  * optional local directories containing custom delta vocabulary CSV files
  * only non-empty entries are loaded
* `custom_delta_project_1` / `custom_delta_dataset_1` ... `custom_delta_project_4` / `custom_delta_dataset_4`
  * upload targets for each custom delta source
  * each configured directory should have a matching project and dataset

### Run order ###

From the repository root:

```
python scripts/run_workflow.py -e conf/<env>.etlconf -c conf/workflow_ddl.conf
python scripts/run_workflow.py -e conf/<env>.etlconf -c conf/workflow_vocab_upload_ddl.conf
python scripts/run_workflow.py -e conf/<env>.etlconf -c conf/workflow_vocabulary_refresh.conf
```

Replace `<env>` with the environment config to use, such as `dev` or `full`.

### Notes ###

* `conf/workflow_vocabulary_refresh.conf` runs `vocabulary_refresh/upload_vocab_to_bq.py` and then `vocabulary_refresh/create_vocab_views.py`.
* `conf/workflow_vocab_upload_ddl.conf` runs `vocabulary_refresh/run_vocab_upload_ddl.py`.
* The BigQuery datasets must already exist before running `conf/workflow_vocab_upload_ddl.conf` or `conf/workflow_vocabulary_refresh.conf`.
* The uploader loads supported OMOP vocabulary tables directly into the existing target tables for each configured source dataset.
* Athena loading is optional.
* Custom delta loading can be limited to a single folder or expanded to multiple folders by filling only the needed `custom_delta_vocab_dir_*` entries.
* The unified `voc_*` materialized views are built in the view dataset and union Athena plus all configured custom delta datasets.

