CREATE TABLE table_checkpoints (
    table_name TEXT,
    checkpoint_time TIMESTAMP,
    last_pk NUMBER
)

foreach (table_checkpoint in get_table_checkpoints()) {

    do {
        var batch = query_source_db(
            SELECT * FROM table_checkpoint.table_name
            WHERE date_last_modified >= table_checkpoint.checkpoint_time
            ORDER BY date_last_modified ASC, ok ASC
            LIMIT 100;
        );

        var attempt = 0;
        var permanent_batch_failure = false;

        while (attempt < MAX_RETRIES) {

            attempt += 1;

            var transaction = new transaction();

            try {

                transaction.start();
                
                foreach (source_row in batch) {
                    alter_destination_db(
                        UPSERT table_checkpoint.table_name
                        UPDATE IF source_row.date_last_modified > destination_date_last_modified
                    )
                }

                alter_destination_db(
                    UPDATE table_checkpoints
                    SET checkpoint_time = batch.max(date_last_modified)
                    WHERE table_name = table_checkpoint.table_name
                )
            }
            catch(e) {
                transaction.rollback();
                if (e.is_transient && attempt > MAX_RETRIES) {
                    log_warning();
                    increment_transient_error_metric();
                    sleep(BACK_OFF_TIME * attempt);
                }
                else {
                    log_error();
                    increment_permanent_error_metric();
                    permanent_batch_failure = true;
                    break; // if a batch fails we need to stop processing the table.
                }
            }
        }
    } while (!batch.empty && !permanent_batch_failure)
}
