#!/usr/bin/env python3
"""Tests for app-store-whats-new.py against a stand-in for the App Store Connect API."""

import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SCRIPTS = HERE.parent
TEXTS = SCRIPTS.parent / "docs" / "app-store" / "whats-new"
sys.path.insert(0, str(SCRIPTS))

import appstoreconnect  # noqa: E402

spec = importlib.util.spec_from_file_location("app_store_whats_new", SCRIPTS / "app-store-whats-new.py")
whats_new = importlib.util.module_from_spec(spec)
spec.loader.exec_module(whats_new)

TEXT = "Game Boy Printer\nPrints now work.\n\nFixes\n- Saving to Photos"


def version(state, version_id="v1", version_string="1.1", platform="IOS", newer_state=None):
    attributes = {"versionString": version_string, "platform": platform, "appStoreState": state}
    if newer_state:
        attributes["appVersionState"] = newer_state
    return {"type": "appStoreVersions", "id": version_id, "attributes": attributes}


def localization(locale="en-US", whats_new=None, localization_id="l1"):
    return {"type": "appStoreVersionLocalizations", "id": localization_id,
            "attributes": {"locale": locale, "whatsNew": whats_new}}


class StubClient(appstoreconnect.Client):
    """Answers from fixed responses by method and path, records every request, and never signs or
    sends one."""

    def __init__(self, versions, localizations=None, patched=None):
        super().__init__("key", "issuer", "/nonexistent")
        self.versions = versions
        self.localizations = localizations if localizations is not None else {"data": [localization()]}
        self.patched = patched
        self.calls = []

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        route = path.partition("?")[0]
        if method == "GET" and route == "/apps":
            return {"data": [{"type": "apps", "id": "app1", "attributes": {"bundleId": appstoreconnect.BUNDLE_ID}}]}
        if method == "GET" and route == "/apps/app1/appStoreVersions":
            return self.versions
        if method == "GET" and route == "/appStoreVersions/v1/appStoreVersionLocalizations":
            return self.localizations
        if method == "PATCH" and route == "/appStoreVersionLocalizations/l1":
            return self.patched if self.patched is not None else body
        raise AssertionError(f"unexpected request {method} {path}")

    def writes(self):
        return [call for call in self.calls if call[0] != "GET"]


class AppStoreWhatsNewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def publish(self, client, apply=True, text=TEXT):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            whats_new.publish(client, "1.1", "1.1.txt", text, apply)
        return output.getvalue()

    def refused(self, client, apply=True):
        with self.assertRaises(SystemExit) as refusal, contextlib.redirect_stdout(io.StringIO()):
            whats_new.publish(client, "1.1", "1.1.txt", TEXT, apply)
        self.assertEqual(client.writes(), [])
        return str(refusal.exception.code)

    def write_file(self, content):
        path = self.dir / "1.1.txt"
        path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))
        return path

    def test_an_editable_version_gets_the_text(self):
        for state in sorted(whats_new.EDITABLE):
            with self.subTest(state=state):
                client = StubClient({"data": [version(state, newer_state=state)]},
                                    {"data": [localization("de-DE"), localization(whats_new="Old notes")]})
                output = self.publish(client)
                self.assertEqual(client.writes(), [("PATCH", "/appStoreVersionLocalizations/l1", {"data": {
                    "type": "appStoreVersionLocalizations", "id": "l1", "attributes": {"whatsNew": TEXT},
                }})])
                self.assertIn(f"is {state}", output)
                self.assertIn("en-US What's New in App Store Connect: 9 characters.", output)
                self.assertIn(f"1.1.txt: {len(TEXT)} of 4000 characters.", output)
                self.assertIn(TEXT, output)
                self.assertIn("Wrote the en-US What's New for version 1.1.", output)
        versions = [path for method, path, _ in client.calls if "/appStoreVersions?" in path]
        self.assertEqual(len(versions), 1)
        self.assertIn("filter[versionString]=1.1&filter[platform]=IOS", versions[0])

    def test_a_preview_reads_but_does_not_write(self):
        client = StubClient({"data": [version("PREPARE_FOR_SUBMISSION")]})
        output = self.publish(client, apply=False)
        self.assertEqual(client.writes(), [])
        self.assertEqual([method for method, _, _ in client.calls], ["GET", "GET", "GET"])
        self.assertIn("en-US What's New in App Store Connect: 0 characters.", output)
        self.assertIn(TEXT, output)
        self.assertIn("Preview only, so nothing was written.", output)

    def test_text_already_there_is_not_written_again(self):
        client = StubClient({"data": [version("PREPARE_FOR_SUBMISSION")]}, {"data": [localization(whats_new=TEXT)]})
        self.assertIn("already has this text", self.publish(client))
        self.assertEqual(client.writes(), [])

    def test_a_live_or_submitted_version_is_refused(self):
        for state in ["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PENDING_APPLE_RELEASE",
                      "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_APP_STORE", "IN_REVIEW",
                      "WAITING_FOR_REVIEW", "READY_FOR_REVIEW", "ACCEPTED", "REMOVED_FROM_SALE", "SOMETHING_NEW"]:
            with self.subTest(state=state):
                client = StubClient({"data": [version(state)]})
                self.assertIn(f"Version 1.1 is {state}", self.refused(client))
                # The localization isn't even read.
                self.assertEqual(len(client.calls), 2)

    def test_the_newer_state_must_agree_that_the_version_is_editable(self):
        client = StubClient({"data": [version("PREPARE_FOR_SUBMISSION", newer_state="WAITING_FOR_REVIEW")]})
        self.assertIn("is WAITING_FOR_REVIEW", self.refused(client))

    def test_a_version_without_a_state_is_refused(self):
        client = StubClient({"data": [version(None)]})
        self.assertIn("didn't give version 1.1's state", self.refused(client))

    def test_a_missing_locale_is_refused_and_not_created(self):
        client = StubClient({"data": [version("PREPARE_FOR_SUBMISSION")]},
                            {"data": [localization("en-GB"), localization("de-DE")]})
        self.assertIn("has no en-US localization", self.refused(client))

    def test_ambiguous_matches_are_refused(self):
        cases = {
            "two versions": ({"data": [version("PREPARE_FOR_SUBMISSION"), version("PREPARE_FOR_SUBMISSION", "v2")]},
                             None, "2 iOS versions named 1.1"),
            "two en-US localizations": ({"data": [version("PREPARE_FOR_SUBMISSION")]},
                                        {"data": [localization(), localization(localization_id="l2")]},
                                        "2 en-US localizations"),
            "a second page": ({"data": [version("PREPARE_FOR_SUBMISSION")], "links": {"next": "https://example"}},
                              None, "more than one page"),
        }
        for name, (versions, localizations, message) in cases.items():
            with self.subTest(name):
                self.assertIn(message, self.refused(StubClient(versions, localizations)))

    def test_no_matching_version_is_refused(self):
        for versions in [[], [version("PREPARE_FOR_SUBMISSION", version_string="1.10")],
                         [version("PREPARE_FOR_SUBMISSION", platform="MAC_OS")]]:
            with self.subTest(versions=versions):
                self.assertIn("has no iOS version 1.1", self.refused(StubClient({"data": versions})))

    def test_an_unexpected_response_shape_is_refused(self):
        editable = {"data": [version("PREPARE_FOR_SUBMISSION")]}
        for name, versions, localizations in [
            ("no data", {"errors": []}, None),
            ("data is not a list", {"data": version("PREPARE_FOR_SUBMISSION")}, None),
            ("wrong type", {"data": [dict(version("PREPARE_FOR_SUBMISSION"), type="builds")]}, None),
            ("id that is not an ID", {"data": [dict(version("PREPARE_FOR_SUBMISSION"), id="../apps")]}, None),
            ("no attributes", {"data": [{"type": "appStoreVersions", "id": "v1"}]}, None),
            ("localization without attributes", editable,
             {"data": [{"type": "appStoreVersionLocalizations", "id": "l1"}]}),
            ("whatsNew is not text", editable, {"data": [localization(whats_new=["a"])]}),
        ]:
            with self.subTest(name):
                self.assertIn("unexpected shape", self.refused(StubClient(versions, localizations)))

    def test_a_write_that_does_not_come_back_unchanged_fails(self):
        client = StubClient({"data": [version("PREPARE_FOR_SUBMISSION")]},
                            patched={"data": {"attributes": {"whatsNew": "Other"}}})
        with self.assertRaises(SystemExit) as failure, contextlib.redirect_stdout(io.StringIO()):
            whats_new.publish(client, "1.1", "1.1.txt", TEXT, True)
        self.assertIn("didn't return the same text", str(failure.exception.code))

    def test_the_text_file_is_read_without_its_final_newline(self):
        self.assertEqual(whats_new.read_text(self.write_file(TEXT + "\n")), TEXT)
        self.assertEqual(whats_new.read_text(self.write_file(TEXT)), TEXT)
        self.assertEqual(whats_new.read_text(self.write_file("Caf\u00e9 \u2615\n")), "Caf\u00e9 \u2615")

    def test_the_length_limit_counts_every_character(self):
        self.assertEqual(len(whats_new.read_text(self.write_file("a" * 4000 + "\n"))), 4000)
        for text in ["a" * 4001, "a" * 3999 + "\U0001F3AE"]:
            with self.subTest(length=len(text)), self.assertRaises(SystemExit) as refusal:
                whats_new.read_text(self.write_file(text))
            self.assertIn("at most 4000", str(refusal.exception.code))

    def test_text_that_is_not_plain_is_refused(self):
        for name, content, message in [
            ("empty", "", "is empty"),
            ("only newlines", "\n\n", "is empty"),
            ("leading blank line", "\n" + TEXT, "starts or ends"),
            ("trailing blank line", TEXT + "\n\n", "starts or ends"),
            ("trailing space", TEXT + " ", "starts or ends"),
            ("tab", "Fixes\n-\tOne", "line 2 has the character U+0009"),
            ("carriage return", "One\r\nTwo", "line 1 has the character U+000D"),
            ("escape", "One \x1b[1mTwo", "U+001B"),
            ("byte order mark", "\ufeffOne", "U+FEFF"),
            ("zero-width space", "One\u200bTwo", "U+200B"),
            ("line separator", "One\u2028Two", "U+2028"),
            ("not UTF-8", b"Caf\xe9", "isn't UTF-8"),
        ]:
            with self.subTest(name), self.assertRaises(SystemExit) as refusal:
                whats_new.read_text(self.write_file(content))
            self.assertIn(message, str(refusal.exception.code))

    def test_a_missing_file_is_refused(self):
        with self.assertRaises(SystemExit) as refusal:
            whats_new.read_text(self.dir / "9.9.txt")
        self.assertIn("doesn't exist", str(refusal.exception.code))

    def test_every_committed_text_is_valid(self):
        texts = sorted(TEXTS.glob("*.txt"))
        self.assertTrue(texts)
        for path in texts:
            with self.subTest(path=path.name):
                self.assertTrue(whats_new.VERSION.fullmatch(path.stem))
                whats_new.read_text(path)


if __name__ == "__main__":
    unittest.main()
