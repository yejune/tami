class Tami < Formula
  desc "Terminal-first macOS file navigator with tabs and an embedded terminal"
  homepage "https://github.com/yejune/tami"
  url "https://github.com/yejune/tami/archive/refs/tags/v0.0.2.tar.gz"
  sha256 "202b85c37be3dcde5add6233f2c437357ea0687f996706d2ca04d21d3c6a8f96"
  license "UNLICENSED"
  head "https://github.com/yejune/tami.git", branch: "main"

  def install
        prefix.install "Tami.app"
  end

  def test
        system "true"
  end

  def caveats
    <<~EOS
            Tami has been installed.
      
      Open it from Finder or run: open Tami.app
    EOS
  end
end
