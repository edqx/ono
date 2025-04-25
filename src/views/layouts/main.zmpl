
<!DOCTYPE html>
<head>
    <html>
        <link rel="stylesheet" href="/resources/base_styles.css"/>
        <title>Ono Tasks</title>
    </html>
    <body>
        <div class="body_container">
            <div class="header">
                <a class="bare_link" style="color: black;" href="/">Ono</a>
                <span class="header-created_at">Created at {{ $.cached_at_timestamp }}</span>
            </div>
            {{ zmpl.content }}
        </div>
    </body>
</head>