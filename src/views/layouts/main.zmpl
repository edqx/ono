
<!DOCTYPE html>
<head>
    <html>
        <link rel="stylesheet" href="/resources/base_styles.css"/>
    </html>
    <body>
        <div class="body_container">
            <div class="header">
                <span>Ono</span>
                <span class="header-created_at">Created at {{ $.cached_at_timestamp }}</span>
            </div>
            {{ zmpl.content }}
        </div>
    </body>
</head>