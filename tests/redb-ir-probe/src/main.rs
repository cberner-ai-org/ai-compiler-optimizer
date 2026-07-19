use redb::{Database, ReadableDatabase, TableDefinition};

const TABLE: TableDefinition<&[u8], &[u8]> = TableDefinition::new("probe");

fn main() {
    let path = std::env::args().nth(1).expect("database path");
    let database = Database::create(path).unwrap();

    let write = database.begin_write().unwrap();
    {
        let mut table = write.open_table(TABLE).unwrap();
        table
            .insert(b"abcdefghijklmnopqrstuvwx".as_slice(), b"value".as_slice())
            .unwrap();
        table
            .remove(b"zyxwvutsrqponmlkjihgfedc".as_slice())
            .unwrap();
    }
    write.commit().unwrap();

    let read = database.begin_read().unwrap();
    let table = read.open_table(TABLE).unwrap();
    std::hint::black_box(table.get(b"abcdefghijklmnopqrstuvwx".as_slice()).unwrap());
}
