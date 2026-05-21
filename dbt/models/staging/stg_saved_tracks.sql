with source as (

    select
        added_at,
        track
    from {{ source('raw', 'saved_tracks') }}

),

renamed as (

    select
        added_at,
        cast(json_value(track, '$.duration_ms') as int64) as duration_ms,
        cast(json_value(track, '$.explicit') as bool) as explicit,
        datetime(added_at, 'Asia/Tokyo') as added_datetime,
        date(added_at, 'Asia/Tokyo') as added_date,
        json_value(track, '$.id') as track_id,
        json_value(track, '$.name') as track_name,
        json_value(track, '$.external_urls.spotify') as spotify_url,
        json_value(track, '$.external_ids.isrc') as isrc,
        json_value(track, '$.album.id') as album_id,
        json_value(track, '$.album.name') as album_name,
        json_value(track, '$.album.album_type') as album_type,
        json_value(track, '$.album.release_date') as album_release_date,
        json_query(track, '$.artists') as artists
    from source

)

select * from renamed
