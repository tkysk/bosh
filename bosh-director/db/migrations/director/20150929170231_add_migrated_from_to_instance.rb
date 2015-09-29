Sequel.migration do
  change do
    alter_table(:instances) do
      add_column :migrated_from, String, text: true
    end
  end
end
