load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

ActionArgsInfo = provider(
    fields = {
        "argv_map": "A dict with compile action arguments keyed by the target label",
    },
)

def _action_argv_aspect_impl(target, ctx):
    argv_map = {}
    if ctx.rule.kind == ctx.attr._target_rule:
        _cpp_commands_args = []
        for action in target.actions:
            if action.mnemonic == ctx.attr._action:
                _cpp_commands_args.extend(action.argv)

        if len(_cpp_commands_args):
            argv_map = dicts.add(
                argv_map,
                {
                    target.label.name: _cpp_commands_args,
                },
            )
    elif ctx.rule.kind in ctx.attr._attr_aspect_dict.keys():
        attrs = ctx.attr._attr_aspect_dict.get(ctx.rule.kind, [])
        for attr_name in attrs:
            value = getattr(ctx.rule.attr, attr_name)
            vlist = value if type(value) == type([]) else [value]
            for value in vlist:
                argv_map = dicts.add(
                    argv_map,
                    value[ActionArgsInfo].argv_map,
                )
    return ActionArgsInfo(
        argv_map = argv_map,
    )

def _get_attr_aspects_list(attr_aspects_dict):
    return sets.to_list(
        sets.make(
            [attr for rule in attr_aspects_dict.values() for attr in rule],
        ),
    )

# The aspects generated by this function are used to examine compile actions
# from cc_library targets generated by our macros for the purpose of assessing
# the results of transitions. Checking the targets directly using their names
# gives info from before the transition is applied.
# attr_aspects should be a dict where the keys are the names of rules and the
# values are lists of attrs that should be traversed by the aspect looking for
# cc_library targets.
def compile_action_argv_aspect_generator(attr_aspects):
    return aspect(
        implementation = _action_argv_aspect_impl,
        attr_aspects = _get_attr_aspects_list(attr_aspects),
        attrs = {
            "_attr_aspect_dict": attr.string_list_dict(default = attr_aspects),
            "_action": attr.string(default = "CppCompile"),
            "_target_rule": attr.string(default = "cc_library"),
        },
    )

def link_action_argv_aspect_generator(attr_aspects, target_rule):
    return aspect(
        implementation = _action_argv_aspect_impl,
        attr_aspects = _get_attr_aspects_list(attr_aspects),
        attrs = {
            "_attr_aspect_dict": attr.string_list_dict(default = attr_aspects),
            "_action": attr.string(default = "CppLink"),
            "_target_rule": attr.string(default = target_rule),
        },
    )

def transition_deps_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    argv_map = target_under_test[ActionArgsInfo].argv_map

    for target in ctx.attr.targets_with_flag:
        asserts.true(
            env,
            target in argv_map,
            "can't find {} in argv map".format(target),
        )
        if target in argv_map:
            argv = argv_map[target]
            for flag in ctx.attr.flags:
                asserts.true(
                    env,
                    flag in argv,
                    "Action of {} didn't have {} flag but it was expected".format(
                        target,
                        flag,
                    ),
                )
    for target in ctx.attr.targets_without_flag:
        asserts.true(
            env,
            target in argv_map,
            "can't find {} in argv map".format(target),
        )
        if target in argv_map:
            argv = argv_map[target]
            for flag in ctx.attr.flags:
                asserts.true(
                    env,
                    flag not in argv,
                    "Action of {} had {} flag but it wasn't expected".format(
                        target,
                        flag,
                    ),
                )
    return analysistest.end(env)

transition_deps_test_attrs = {
    "targets_with_flag": attr.string_list(),
    "targets_without_flag": attr.string_list(),
    "flags": attr.string_list(),
}
