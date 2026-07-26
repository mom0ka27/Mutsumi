from http import HTTPStatus


class QBittorrentError(Exception):
    """Business error raised while talking to qBittorrent.

    ``status_code`` is the HTTP status sent to the client, so these failures
    behave like every other error in the API. ``code`` stays in the response
    body for clients that need to branch on the specific reason.
    """

    def __init__(
        self,
        code: int,
        msg: str,
        status_code: int = HTTPStatus.BAD_GATEWAY,
    ):
        self.code = code
        self.msg = msg
        self.status_code = int(status_code)
        super().__init__(msg)
