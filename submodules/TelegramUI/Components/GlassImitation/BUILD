load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
    "apple_resource_group",
)
load("//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)


filegroup(
    name = "GlassImitationMetalSources",
    srcs = glob([
        "Metal/**/*.metal",
    ]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "GlassImitationResources",
    srcs = glob([
        "Resources/**/*.json",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "GlassImitationMetalSourcesBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.GlassImitationMetalSources</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>GlassImitation</string>
    """
)

apple_resource_bundle(
    name = "GlassImitationMetalSourcesBundle",
    infoplists = [
        ":GlassImitationMetalSourcesBundleInfoPlist",
    ],
    resources = [
        ":GlassImitationMetalSources",
        ":GlassImitationResources",
    ],
)

swift_library(
    name = "GlassImitation",
    module_name = "GlassImitation",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":GlassImitationMetalSourcesBundle",
    ],
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)
