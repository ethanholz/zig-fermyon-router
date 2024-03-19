{ linkFarm, fetchFromGitHub }:

linkFarm "zig-packages" [
  {
    name = "12204cfebcccb9fb8a5c7b4a6ec663aea691d180f7d346d36f213b4e154a6be1f823";
    path = fetchFromGitHub {
      owner = "andrewrk";
      repo = "mime";
      rev = "ef4381c6a739ca9d44fb7aa6b14c66e1fba2e16d";
      hash = "sha256-EHmM+inIpyp0iWLPfLS40Iyi4fy+kv+zmI6mg1WgmaM";
    };
  }

]
