with source as (

    select
        artist_id,
        artist
    from {{ source('raw', 'artists') }}

),

renamed as (

    select
        artist_id,
        cast(json_value(artist, '$.popularity') as int64) as popularity,
        json_value(artist, '$.name') as artist_name,
        json_query(artist, '$.genres') as genres
    from source

)

select * from renamed
